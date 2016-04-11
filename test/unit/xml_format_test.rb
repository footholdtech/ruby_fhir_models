require_relative "../simplecov"
require_relative '../../lib/fhir_models'

require 'fileutils'
require 'pry'
require 'nokogiri/diff'
require 'minitest/autorun'
require 'bundler/setup'
require 'test/unit'

class XmlFormatTest < Test::Unit::TestCase
 
  # turn off the ridiculous warnings
  $VERBOSE=nil

  ERROR_DIR = File.join('errors', 'XmlFormatTest')
  ERROR_LOSSY_DIR = File.join('errors', 'XmlLossinessTest')
  EXAMPLE_ROOT = File.join('examples','xml')

  # Automatically generate one test method per example file
  example_files = File.join(EXAMPLE_ROOT, '**', '*.xml')

  # Create a blank folder for the errors
  FileUtils.rm_rf(ERROR_DIR) if File.directory?(ERROR_DIR)
  FileUtils.mkdir_p ERROR_DIR
  FileUtils.rm_rf(ERROR_LOSSY_DIR) if File.directory?(ERROR_LOSSY_DIR)
  FileUtils.mkdir_p ERROR_LOSSY_DIR
    
  Dir.glob(example_files).each do | example_file |
    example_name = File.basename(example_file, ".xml")
    define_method("test_xml_format_#{example_name}") do
      run_xml_roundtrip_test(example_file, example_name)
    end
    define_method("test_xml_json_xml_lossiness_#{example_name}") do
      run_xml_json_xml_lossiness_test(example_file, example_name)
    end
  end

  def run_xml_roundtrip_test(example_file, example_name)
    input_xml = File.read(example_file)
    resource = FHIR::Xml.from_xml(input_xml)
    output_xml = resource.to_xml

    input_nodes = Nokogiri::XML(input_xml)
    output_nodes = Nokogiri::XML(output_xml)

    clean_nodes(input_nodes.root)
    clean_nodes(output_nodes.root)

    errors = calculate_errors(input_nodes,output_nodes)
    if !errors.empty?
      File.open("#{ERROR_DIR}/#{example_name}.err", 'w:UTF-8') {|file| file.write(errors.map{|x| "#{x.first} #{x.last.to_xml}"}.join("\n"))}
      File.open("#{ERROR_DIR}/#{example_name}_PRODUCED.xml", 'w:UTF-8') {|file| file.write(output_xml)}
      File.open("#{ERROR_DIR}/#{example_name}_ORIGINAL.xml", 'w:UTF-8') {|file| file.write(input_xml)}
    end

    assert errors.empty?, "Differences in generated XML vs original"
  end

  def run_xml_json_xml_lossiness_test(example_file, example_name)
    input_xml = File.read(example_file)
    resource_from_xml = FHIR::Xml.from_xml(input_xml)
    output_json = resource_from_xml.to_json
    resource_from_json = FHIR::Json.from_json(output_json)
    output_xml = resource_from_json.to_xml

    input_nodes = Nokogiri::XML(input_xml)
    output_nodes = Nokogiri::XML(output_xml)

    clean_nodes(input_nodes.root)
    clean_nodes(output_nodes.root)

    errors = calculate_errors(input_nodes,output_nodes)
    if !errors.empty?
      File.open("#{ERROR_LOSSY_DIR}/#{example_name}.err", 'w:UTF-8') {|file| file.write(errors.map{|x| "#{x.first} #{x.last.to_xml}"}.join("\n"))}
      File.open("#{ERROR_LOSSY_DIR}/#{example_name}_PRODUCED.xml", 'w:UTF-8') {|file| file.write(output_xml)}
      File.open("#{ERROR_LOSSY_DIR}/#{example_name}_ORIGINAL.xml", 'w:UTF-8') {|file| file.write(input_xml)}
    end

    assert errors.empty?, "Differences in generated XML vs original"
  end

  def calculate_errors(input_nodes,output_nodes)
    errors = input_nodes.diff(output_nodes, added: true, removed: true).to_a
    errors.keep_if do |error|
      # we do not support the preservation of comments, ignore them
      is_comment = (error.last.class==Nokogiri::XML::Comment)
      # we do not care about empty whitespace
      is_empty_text = (error.last.class==Nokogiri::XML::Text && error.last.text.strip=='')
      # we do not support internal element ids, ignore them
      is_internal_element_id = (error.last.class==Nokogiri::XML::Attr && error.last.name=='id')
      !(is_comment || is_empty_text || is_internal_element_id)
    end
    errors
  end

  # process input to remove leading and trailing newlines and whitespace around text
  def clean_nodes(node)
    node.children.each do |child|
      child.content = child.content.strip if(child.is_a?(Nokogiri::XML::Text))
      if child.has_attribute?('value')
        # remove all the children -- these will be primitive extensions which we do not support.
        child.children = ''
      end
      clean_nodes(child) if !child.children.empty?
    end
  end

end

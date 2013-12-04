# hprcu provider

# Memo: debugging techniques:
#
# require 'ruby-debug';debugger
#
# set_trace_func proc { |event, file, line, id, binding, classname|
#   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
# }
#
# $x = inline_template("<%= require 'ruby-debug';debugger; puts 'foo' %>")

require 'puppet'
require 'rexml/document'
require 'open3'
require 'xml/xslt'
require 'erb'
require 'tempfile'

Puppet::Type.type(:hprcu).provide(:hprcu) do
#  commands :hprcu => '/usr/bin/hprcu'
  commands :hprcu => '/sbin/hp-rcu'
# For testing:
#  commands :hprcu => '/home/toby/Dev/Puppet/puppet-hprcu/fakehprcu'

  # No XML until fetched
  $hprcuXml = nil

  # Record any changes made by the provider
  $changes = []

  $xsltTemplate = <<EOT
<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

    <!-- IdentityTransform -->
    <xsl:template match="/|@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="/hprcu/feature[@feature_id='<%= featureId %>']">
        <feature feature_id='<%= featureId %>' selected_option_id='<%= selectedOptionId %>'  sys_default_option_id='<%= sysDefaultOptionId %>' feature_type='option'>
      <xsl:copy-of select="node()"/>
    </feature>
    </xsl:template>
</xsl:stylesheet>
EOT

  # This is a modified version of mk_resource_methods from provider.rb
  def self.my_mk_resource_methods
    [resource_type.validproperties, resource_type.parameters].flatten.each do |attr|
      if attr.class != Symbol
        attr = attr.intern
      end
      next if attr == :name
      define_method(attr) do
        @property_hash[attr] || :absent
      end

      define_method(attr.to_s + "=") do |val|
        @property_flush[attr] = val
      end
    end
  end

  my_mk_resource_methods

  # Map from (e.g.) 'Intel(R) Hyperthreading Options' to 'intelrhyperthreadingoptions'
  # Note that the names of setter methods must be 'Puppet-friendly', i.e. valid as per 
  # grammar.ra in the Puppet source
  $map2Valid = {} 
  def self.makeValid(invalid)
    if ! $map2Valid.has_key?(invalid)
      # Make into a valid puppet symbol by:
      # 1) Removing special characters
      # 2) Prepending 'i' if it starts with digits
      # 3) Removing dots if it ends with dots + numbers
      valid = invalid.gsub(/[- ()_\/:;,]/,'').sub(/^([0-9]+)/, 'i\1').sub(/\.([0-9]+)$/, '\1')
      $map2Valid[invalid] = valid
    end
    $map2Valid[invalid]
  end

  def exists?
    # Must return 'true' here because as per p.46 of 'Puppet Types & Providers':
    #   "properties other than ensure are only *individually* managed when ensure
    #   is set to present and the resource already exists. When a resource state
    #   is absent, Puppet ignores any specified resource property."
    true # Equivalent to: @property_hash[:ensure] == :present, because we 
         # force {:ensure => :present} in self.instances
  end

  def self.instances
    # This method does several things:
    # * reads the XML that is output by hprcu 
    # * gathers a list of the names of the features (i.e. BIOS settings)
    # * for each feature it gathers the possible options, the current and default options

    if $hprcuXml.nil?
      self.fetchXml
    end

    $property2FeatureIdMap = {}
    $value2SelectionOptionIdMap = {}
    $propertyName2SysDefaultOptionIdMap = {}
    propertyLookup = {}

    # Set some other properties that don't come from the XML
    propertyLookup[:name] = 'default'
    # Force :ensure = :present because, as per p.46 of 'Puppet Types & Providers':
    #   "properties other than ensure are only *individually* managed when ensure
    #   is set to present and the resource already exists. When a resource state
    #   is absent, Puppet ignores any specified resource property."
    propertyLookup[:ensure] = :present

    # Iterate over features in populate propertyLookup in preparation for creating 
    # a new object with the properties and their values defined
    $hprcuXml.elements.each('/hprcu/feature[@feature_type="option"]') { |feature|
      featureName = makeValid(feature.elements['feature_name'].text.downcase).to_sym
      $property2FeatureIdMap[featureName] = feature.attributes['feature_id']

      $value2SelectionOptionIdMap[featureName] = {}
      sysDefaultOptionId = feature.attributes['sys_default_option_id']
      $propertyName2SysDefaultOptionIdMap[featureName] = sysDefaultOptionId

      optionName2Id = {}
      feature.get_elements('option').each { |option| 
        optionId = option.attributes['option_id']
        optionName = makeValid(option.elements['option_name'].text).to_sym
        optionName2Id[optionName] = optionId
      }
      $value2SelectionOptionIdMap[featureName] = optionName2Id

      selectedOptionId = feature.attributes['selected_option_id']
      optionId2Name = optionName2Id.invert
      propertyLookup[featureName] = optionId2Name[selectedOptionId]
    } 

    # Return an array containing a single instance of the resource (by definition there 
    # is only only one instance of the BIOS settings per host)
    [ new(propertyLookup) ]
  end

  def self.fetchXml
    tempfile = Tempfile.new('puppethprcu')
    tempfile.close
    hprcu('-s', '-f', tempfile.path)

    hprcuFileHandle = File.open(tempfile.path, 'r');
    $hprcuXml = REXML::Document.new hprcuFileHandle.read()
    hprcuFileHandle.close
  end

  def self.prefetch(resources)
    Puppet.debug('self.prefetch')

    hprcus = instances
    resources.keys.each do |name|
      if provider = instances.find{ |inst| inst.name == name }
        resources[name].provider = provider
      end
    end
  end

  def modifyXml(property)
    # Referring to the data gathered earlier by self.instances, this function
    # looks up the option_id of the new option value and modifies the XML in
    # hprcuXml to reflect the new selection
    newValue = @property_flush[property]

    featureId = $property2FeatureIdMap[property]
    selectedOptionId = $value2SelectionOptionIdMap[property][newValue]
    sysDefaultOptionId = $propertyName2SysDefaultOptionIdMap[property]

    xslt = XML::XSLT.new()
    xslt.xml = $hprcuXml
    xslt.xsl = ERB.new($xsltTemplate).result(binding)
    $hprcuXml = REXML::Document.new xslt.serve()
  end

  def flush
    recordOfChange = '/tmp/hprcu_changes'
    recordFile = File.open(recordOfChange, 'a')
    @property_flush.keys.each { |property|
      recordFile.write( sprintf("%s: Changing '%s' to '%s'\n", Time.now, property, @property_flush[property] ))
      puts sprintf("Changing '%s' to '%s'", property, @property_flush[property])
      $hprcuXml = modifyXml(property)
    }
    recordFile.close

    tempfile = Tempfile.new('puppethprcu')
    tempfile.write($hprcuXml)
    tempfile.close
    hprcu('-l', '-f', tempfile.path)

    @property_hash = resource.to_hash
  end

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end
end

# vim:sw=2:ts=2:et: 

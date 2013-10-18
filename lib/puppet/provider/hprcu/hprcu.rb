# hprcu provider

# Memo: debugging techniques:
#
# require 'ruby-debug';debugger
#
# set_trace_func proc { |event, file, line, id, binding, classname|
#   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
# }

require 'puppet'
require 'rexml/document'
require 'open3'
require 'xml/xslt'
require 'erb'
require 'tempfile'

Puppet::Type.type(:hprcu).provide(:hprcu) do
#    commands :hprcu => '/usr/sbin/hprcu'

    # No XML until fetched
    $hprcuXML = :absent

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
        <feature feature_id='<%= featureId %>' selection_option_id='<%= selectionOptionId %>'  sys_default_option_id='<%= sysDefaultOptionId %>' feature_type='option'>
      <xsl:copy-of select="node()"/>
    </feature>
    </xsl:template>
</xsl:stylesheet>
EOT

  mk_resource_methods

  # Map from (e.g.) 'Intel(R) Hyperthreading Options' to 'intelrhyperthreadingoptions'
  # Note that the names of the setters must be 'Puppet-friendly', i.e. valid 
  # as per grammar.ra in the Puppet source
  $map2Valid = {} 
  def self.makeValid(invalid)
    if ! $map2Valid.has_key?(invalid)
      valid = invalid.downcase.gsub(/[- ()_\/:;]/,'')
      $map2Valid[invalid] = valid
    end
    $map2Valid[invalid]
  end

  def exists?
    # Must return 'true' here because as per p.46 of Puppet Types & Providers:
    # "properties other than ensure are only *individually* managed when ensure
    # is set to present and the resource already exists. When a resource state
    # is absent, Puppet ignores any specified resource property."
    true # Equivalent to: @property_hash[:ensure] == :present, because we 
         # force {:ensure => :present} in self.instances
  end

  def self.instances
    # This method does several things:
    # * reads the XML that is output by hprcu 
    # * gathers a list of the names of the features (i.e. BIOS settings)
    # * for each feature it gathers the possible options, the current and default options
    #
    # So it needs hashes mapping:
    #   property => featureId
    #   newValue => selectionOptionId
    #   property => sysDefaultOptionId

    if $hprcuXml.nil?
      $hprcuXml = self.fetchXml
    end

    $propertyFeatureIdMap = [

    ]

    $valueSelectionOptionIdMap = [

    ]

    $propertySysDefaultOptionIdMap = [

    ]
    
    


    # Create a new instance of the provider describing the current state
    propertyLookup = {}

    $hprcuXml.elements.each('/hprcu/feature') { |feature|
      selectionOptionId = feature.attributes['selection_option_id']
      featureName = feature.elements['feature_name'].text
       
      optionId2Name = {}
      feature.get_elements('option').each { |option| 
        optionId =  option.attributes['option_id']
        optionName = option.get_elements('option_name').first.get_text.to_s
        optionId2Name[optionId] = makeValid(optionName)
      }
  
      propertyLookup[makeValid(featureName).to_sym] = optionId2Name[selectionOptionId].to_sym
    }
  
    # Return an array containing a single instance of the resource (by definition there 
    # is only only one instance of the BIOS parameters on the host)
    [
      new (
        :name                => 'default',
        # Force :ensure => :present because as per p.46 of Puppet Types & Providers:
        # "properties other than ensure are only *individually* managed when ensure
        # is set to present and the resource already exists. When a resource state
        # is absent, Puppet ignores any specified resource property."
        :ensure              => :present,
        :embeddedserialport  => propertyLookup[:embeddedserialport],
        :virtualserialport   => propertyLookup[:virtualserialport]
      ) 
    ]
  end

  def self.fetchXml
    hprcuFilename = '/home/toby/Dev/Puppet/puppet-hprcu/hprcu_sample.xml'
    hprcuFileHandle = File.open(hprcuFilename, 'r');
    $hprcuXml = REXML::Document.new hprcuFileHandle.read()
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

#  def flush
#   require 'ruby-debug';debugger
#    tempfile = Tempfile.new('puppethprcu')
#    tempfile.write($hprcuXml)
#    tempfile.close
#
#    # ret = system('/home/toby/Dev/Puppet/prevtec-biostunable/fakeconrep/conrep', '-l', tempfile.path)
#    # TODO: try conrep('-l', tempfile.path)
#    #if ret.nil?
#    # fail("Execution of hprcu flush command failed")
#    #elsif ret == false
#    # warn("hprcu flush command exited with non-zero exit code")
#    #else
#    ##   tempfile.unlink
#    #end
#       
#    # Create a file in /tmp that records the tunable changes made by the provider
#    hprcuUpdateFile = '/tmp/hprcuupdate'
#    File.new(hprcuUpdateFile, File::CREAT|File::TRUNC|File::RDWR, 0644)
#    statusFile = File.open(hprcuUpdateFile, 'w')
#    statusFile.write($changes)
#    statusFile.close()
#
#    @property_hash.clear
#  end

#def flush
#  if @property_flush[:embeddedserialport]
#    puts "Changing :embeddedserialport to %s" % @property_flush[:embeddedserialport]
#  end
#    
#  if @property_flush[:virtualserialport]
#    puts "Changing :virtualserialport to %s" % @property_flush[:virtualserialport]
#  end
#
#  @property_hash = resource.to_hash
#end

  def modifyXml(property)
    require 'ruby-debug';debugger

    # Referring to the data gathered earlier by self.instances, this function
    # looks up the option_id of the new option value and modifies the XML in
    # hprcuXml to reflect the new selection
    #
    # It needs to know the following variables to substitute into the ERB template:
    #   featureId
    #   selectionOptionId
    #   sysDefaultOptionId
    #
    # So it needs hashes mapping:
    #   property => featureId
    #   newValue => selectionOptionId
    #   property => sysDefaultOptionId

    newValue = @property_flush[value]

  end

  def flush
    @property_flush.keys.each { |property|
      puts sprintf("Changing %s to %s", property, @property_flush[property])
      $hprcuXml = modifyXml(property)
    }
    @property_hash = resource.to_hash
  end

  def initialize(value={})
    super(value)
    @property_flush = {}
  end

  # Definitions of property-setters
  # Note that the names of the setters must be 'Puppet-friendly', i.e. valid 
  # as per grammar.ra in the Puppet source
  def embeddedserialport=(value)
    @property_flush[:embeddedserialport] = value
  end

  def virtualserialport=(value)
    @property_flush[:virtualserialport] = value
  end

#  def embeddedserialport=(value)
#    featureId = 23
#    sysDefaultOptionId = 1
#    optionName2Id = {
#      :com1irq4io3f8h3ffh => 1,
#      :com2irq3io2f8h2ffh => 2,
#      :com3irq5io3e8h3efh => 3,
#      :disabled => 4,
#    }
#    selectionOptionId = optionName2Id[value]  
#
#    xslt = XML::XSLT.new()
#
#    xslt.xml = $hprcuXml
#    xslt.xsl = ERB.new($xsltTemplate).result(binding)
#
#    $changes.push("Changed value for 'embeddedserialport' to '#{value}'\n")
#
#      require 'ruby-debug';debugger
#    $hprcuXml = REXML::Document.new xslt.serve()
#
#    @property_hash[:embeddedserialport] = value
#  end
#
#  def virtualserialport=(value)
#    featureId = 85
#    sysDefaultOptionId = 2
#    optionName2Id = {
#      :com1irq4io3f8h3ffh => 1,
#      :com2irq3io2f8h2ffh => 2,
#      :com3irq5io3e8h3efh => 3,
#      :disabled => 4,
#    }
#    selectionOptionId = optionName2Id[value]  
#
#    xslt = XML::XSLT.new()
#
#    xslt.xml = $hprcuXml
#    xslt.xsl = ERB.new($xsltTemplate).result(binding)
#
#    $changes.push("Changed value for 'virtualserialport' to '#{value}'\n")
#
#      require 'ruby-debug';debugger
#    $hprcuXml = REXML::Document.new xslt.serve()
#    @property_hash[:virtualserialport] = value
#  end
end

# vim:sw=2:ts=2:et: 

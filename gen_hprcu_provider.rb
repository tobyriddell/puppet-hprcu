#!/usr/bin/ruby
#
# Use hprcu XML output to generate hprcu provider
#
# Implementation plan:
# 1. Scan XML, for each feature encountered, extract the feature name and id and 
#    convert into Puppet-friendly form (to name the setter), scan the options and 
#    output a hash mapping option to option id. Use this data to generate a setter
#    for each feature.
# 3. Output preamble, setters and post-amble code
#
# Potential optimisation: the setters generate the XSL (adding the transforms that
# match the change they're making) and the resulting XSL is applied to the XML in
# the flush function.
#
# Outline:
# def self.fetchXML
#     # If hprcu has not already been run, then run it and return the XML,
# ...
# end
#         
# def a20m=(value)
# ...
# end
# 
# def self.instances
#     # Return an array consisting of an instance of the resource named 'default'
#     [new(:name => :default)]
# end
# 
# def self.prefetch(resources)
#     Puppet.debug('self.prefetch')
#     @property_hash = {}
# ...
# end
# 
# def flush
#     Puppet.debug('flush')
#     # Open temp. file
# ...
# end

require 'puppet'
require 'rexml/document'
require 'xml/xslt'
require 'erb'

$unfriendly2Friendly = {} # Map between (e.g.) 'Intel(R) Hyperthreading Options' and 'intelrhyperthreadingoptions'

# Generate (and remember) a Puppet-friendly feature name, or if one already exists just 
# return it
def puppetFriendly(unfriendly)
	if ! $unfriendly2Friendly.has_key?(unfriendly)
		friendly = unfriendly.downcase.gsub(/[- ()_\/:;]/,'')
		$unfriendly2Friendly[unfriendly] = friendly
	end
	$unfriendly2Friendly[unfriendly]
end

# Scan XML generating (and saving) Puppet friendly feature names using puppetFriendly()
def generatePuppetFriendlyLookup
    $hprcuXml.root.elements.each('/hprcu/feature') { |feature| 
    	propertyName = ''
    	feature.elements.each('feature_name') { |feature_name| 
    		propertyName = ':' + puppetFriendly(feature_name.text)
    	}
		feature.attributes['selection_option_id']
    	# $unfriendly2Friendly now contains a map of the unfriendly/friendly names
    }
end

hprcuFilename = 'hprcu_sample.xml'
hprcuFileHandle = File.open('hprcu_sample.xml', 'r');
$hprcuXml = REXML::Document.new hprcuFileHandle.read()

# Start of the provider code
$preamble = <<EOP 
# hprcu provider

require 'puppet'
require 'rexml/document'
require 'open3'
require 'xml/xslt'
require 'erb'
require 'tempfile'

Puppet::Type.type(:hprcu).provide(:hprcu) do
#    commands :hprcu => '/usr/sbin/hprcu'

	mk_resource_methods

    # No XML until fetched
    $hprcuXML = :absent

    # Record changes as they are made
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
        <feature feature_id='<%= featureId %>' selection_option_id='<%= selectionOptionId %>' feature_type='option'>
			<xsl:copy-of select="node()"/>
		</feature>
    </xsl:template>
</xsl:stylesheet>
EOT

    $unfriendly2Friendly = {} # Map between (e.g.) 'Intel(R) Hyperthreading Options' and 'intelrhyperthreadingoptions'
    
    # Generate (and remember) a Puppet-friendly feature name, or if one already exists just 
    # return it
    def self.puppetFriendly(unfriendly)
    	if ! $unfriendly2Friendly.has_key?(unfriendly)
    		friendly = unfriendly.downcase.gsub(/[- ()_\\/:;]/,'')
    		$unfriendly2Friendly[unfriendly] = friendly
    	end
    	$unfriendly2Friendly[unfriendly]
    end

    def self.instances
        # Return an array consisting of an instance of the resource named 'default'
        [new(:name => :default)]
    end

	def self.fetchXml
        hprcuFilename = 'hprcu_sample.xml'
        hprcuFileHandle = File.open('hprcu_sample.xml', 'r');
        $hprcuXml = REXML::Document.new hprcuFileHandle.read()
	end

    def self.prefetch(resources)
        Puppet.debug('self.prefetch')
        @property_hash = {}
    
        if $hprcuXml.nil?
            $hprcuXml = self.fetchXml
        end

        $hprcuXml.root.elements.each('/hprcu/feature') { |feature|
    		require 'ruby-debug';debugger
    		selectionOptionId = feature.attributes['selection_option_id']
    		featureName = feature.elements['feature_name'].text
    	
    		optionId2Name = {}
    		feature.get_elements('option').each { |option| 
    			optionId =  option.attributes['option_id']
    			optionName = option.get_elements('option_name').first.get_text.to_s
    			optionId2Name[optionId] = puppetFriendly(optionName)
    		}
    		@property_hash[puppetFriendly(featureName)] = optionId2Name[selectionOptionId]
        }
    end

	def flush
		require 'ruby-debug';debugger
        tempfile = Tempfile.new('puppethprcu')
        tempfile.write($hprcuXML)
        tempfile.close

        # ret = system('/home/toby/Dev/Puppet/prevtec-biostunable/fakeconrep/conrep', '-l', tempfile.path)
        # TODO: try conrep('-l', tempfile.path)
        #if ret.nil?
        #	fail("Execution of hprcu flush command failed")
        #elsif ret == false
        #	warn("hprcu flush command exited with non-zero exit code")
        #else
        ##   tempfile.unlink
        #end
        
        # Create a file in /tmp that records the tunable changes made by the provider
        hprcuUpdateFile = '/tmp/hprcuupdate'
        File.new(hprcuUpdateFile, File::CREAT|File::TRUNC|File::RDWR, 0644)
        statusFile = File.open(hprcuUpdateFile, 'w')
        statusFile.write($changes)
        statusFile.close()
    end

EOP

pfl = generatePuppetFriendlyLookup

def generateSetters
	output = ""
    $hprcuXml.root.elements.each('/hprcu/feature') { |feature| 
		featureName = ''
	    feature.elements.each('feature_name') { |feature_name|
				featureName = puppetFriendly(feature_name.text)
	            output = output + "\tdef " + featureName + "=(value)\n"
	    }

		output = output +  "\t\tfeatureId = " + feature.attributes['feature_id'] + "\n"

		output = output + "\t\toptionName2Id = {\n"
		optionName = ''
	    feature.elements.each('option') { |option|
	        option.elements.each('option_name') { |on|
				output = output + "\t\t\t:" + puppetFriendly(on.text) + " => " + option.attributes['option_id'] + ",\n"
				optionName = on.text
	        }
	    }
		output = output + "\t\t}\n"

    	feature.elements.each('feature_name') { |feature_name| 
    		propertyName = ':' + puppetFriendly(feature_name.text)
		}

		output = output + <<EOT
		selectionOptionId = optionName2Id[value]	

		xslt = XML::XSLT.new()

		xslt.xml = $hprcuXml
		xslt.xsl = ERB.new($xsltTemplate).result(binding)

		$changes.push("Changed value for '#{featureName}' to '#\{value}'\n")

		$hprcuXml = REXML::Document.new xslt.serve()
	end

EOT
    }
	output
end

#hprcuXml = hyperthreading=(hprcuXml)
#
#puts hprcuXml

# hprcuXml.root.elements.each('/hprcu/feature') { |feature| 
# 	propertyName = ''
# 	validValues = []
# 	propertyHash = {}
# 
# 	feature.elements.each('feature_name') { |feature_name| 
# 		propertyName = ':' + puppetFriendly(feature_name.text)
# 	}
# 
# 	feature.elements.each('option') { |option| 
# 		option.elements.each('option_name') { |on| 
# 			validValues.push(':' + puppetFriendly(on.text))
# 			propertyHash[option.attributes['option_id']] = ':' + puppetFriendly(on.text)
# 		}
# 	}
# 
# 	defaultValue = propertyHash[feature.attributes['sys_default_option_id']]
# 
# 	puts ERB.new($newpropertyTemplate).result(binding)
# }
# 
# puts <<EOT
# end
# EOT

puts $preamble

#require 'ruby-debug';debugger
puts generateSetters

puts "end"

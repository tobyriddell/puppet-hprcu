# hprcu type

Puppet::Type.newtype(:hprcu) do
	@doc = "" # TODO

	# Type must be ensurable as we must use exists?, because as per p. 46 of 
	# Puppet Types and Providers: properties other than ensure are only 
	# *individually* managed when ensure is set to present and the resource 
	# already exists. When a resource state is absent, Puppet ignores any 
	# specified # resource property.
	ensurable

	newparam(:name, :namevar => true) do
	end

	newproperty(:embeddedserialport) do
		newvalues(:com1irq4io3f8h3ffh, :com2irq3io2f8h2ffh, :com3irq5io3e8h3efh, :disabled)
	end

	newproperty(:virtualserialport) do
		newvalues(:com1irq4io3f8h3ffh, :com2irq3io2f8h2ffh, :com3irq5io3e8h3efh, :disabled)
	end

	newproperty(:noexecutememoryprotection) do
		newvalues(:enabled, :disabled)
	end

	newproperty(:intelrhyperthreadingoptions) do
		newvalues(:enabled, :disabled)
	end

	newproperty(:intelrturboboosttechnology) do
		newvalues(:enabled, :disabled)
	end

	newproperty(:thermalconfiguration) do
		newvalues(:optimalcooling, :increasedcooling, :maximumcooling)
	end

end
# vim:sw=2:ts=2:et:

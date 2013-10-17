# hprcu type

Puppet::Type.newtype(:hprcu) do
	Puppet.debug('In top-level (type)')
	@doc = "" # TODO

	# Type must be ensurable as we must use exists?, because as per p. 46 of Puppet Types
	# and Providers: properties other than ensure are only *individually*
	# managed when ensure is set to present and the resource already
	# exists. When a resource state is absent, Puppet ignores any specified
	# resource property.
	ensurable

	newparam(:name, :namevar => true) do
	end

	newproperty(:embeddedserialport) do
#		defaultto :com1irq4io3f8h3ffh
		newvalues(:com1irq4io3f8h3ffh, :com2irq3io2f8h2ffh, :com3irq5io3e8h3efh, :disabled)
	end

	newproperty(:virtualserialport) do
#		defaultto :com2irq3io2f8h2ffh
		newvalues(:com1irq4io3f8h3ffh, :com2irq3io2f8h2ffh, :com3irq5io3e8h3efh, :disabled)
	end
end

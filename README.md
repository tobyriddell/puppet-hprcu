puppet-hprcu
============

Puppet type &amp; provider to modify BIOS of HP servers using hprcu

# Usage

<code>puppet resource hprcu</code>

<code>puppet apply -e "hprcu{ 'default': intelrhyperthreadingoptions = 'enabled' }"</code>

In a manifest:

<code>hprcu { 'default':
	intelrhyperthreadingoptions = 'enabled' 
}</code>

# Design considerations

The ideal situation is to have a single type for managing BIOS settings on hardware from many different vendors. Corresponding providers would handle getting/setting the type's properties for the different platforms. However, the target is moving: vendors call the same BIOS setting by different names, BIOS revisions change the names of settings, new hardware introduces new settings. 

One option is to map between a common setting, such as whether C-states are enabled but what should be done in the case that there's a setting that's only supported by, say, an HP BIOS and not by an Oracle BIOS?

I've chosen to implement a separate type & provider for HP hardware using their hprcu utility. The code for the type can be regenerated automatically using XML output from hprcu. The provider doesn't contain any code that changes if the property-names change and therefore it shouldn't need to be changed so often.

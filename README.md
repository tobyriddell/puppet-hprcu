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

In a class:

<code>class energysaving {
	hprcu { 'default':

	}
}</code>

Note: owing to the fact that there's only one collection of BIOS settings per host, there's only one valid name for the resource: 'default'.

# Design considerations

The ideal situation is to have a single type for managing BIOS settings on hardware from many different vendors. Corresponding providers would handle getting/setting the type's properties for the different platforms. However, the target is moving: vendors call the same BIOS setting by different names, BIOS revisions change the names of settings, new hardware introduces new settings. 

One option is to map between a common setting, such as whether C-states are enabled but what should be done in the case that there's a setting that's only supported by, say, an HP BIOS and not by an Oracle BIOS? Also when the name of a setting changes the mappings would need to be updated and I want to keep maintenance tasks to a minimum.

I've chosen to implement a separate type & provider for HP hardware using their hprcu utility. The code for the type can be regenerated automatically using XML output from hprcu. The provider doesn't contain any code that changes if the property-names change and therefore it shouldn't need to be changed so often.

Because property names are auto-generated from XML output by hprcu, the names can be non-intuitive, for example 'intelrhyperthreadingoptions' instead of plain 'hyperthreading'. As mentioned above, I don't want to have to maintain a static mapping, but as mentioned above I don't want to have to maintain this mapping. It should be possible to determine the name of the property by either inspecting hprcu XML output or by running 'puppet resource hprcu' and checking the list of property names.



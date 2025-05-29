## Raum
Spin-off of an MIT Assistive Tech Club project that I was a part of -- this app is built to navigate visually-inpaired users to certain objects using spatial sound with hardware integration.

It includes accessibility features such as
- text-to-speech input
- voice-over during object recognition 
- spatial hints for locating (supports the apple Dynamic Head Tracking feature on applicable devices)
- start-over with gesture

It is built with a simple iOS native pipeline, integrating coreML, ARkit, and NLEmbedding. Integrated with HRTF (head-related transfer function) to ensure a smooth spatial experience. Hoping to personalize this in the future but the iOS framework is unfortunately too rigid for that. 

# TODO
hardware integrate with UWB trackers. This will allow more accurate navigation to commonly visited places (i.e. car). Airtags unfortunately are not available for 3rd party apps, hoping to integrate with Qorvo or Qualcomm chips in the future instead.

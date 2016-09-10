/**
Copyright: Copyright (c) 2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module capture;

import core.thread : Thread, msecs;
import std.stdio : writefln;
import std.string : fromStringz;

import audio : BufferFormat, CaptureDevice;

void captureStream(
	size_t deviceBufferSize,
	float[] consumerBuffer,
	size_t frequency,
	size_t delayMsecs,
	bool delegate(float[]) dataConsumer)
{
	// Get the name of the 'default' capture device
	const(char)* defaultCaptureDevice = CaptureDevice.defaultDeviceName;
	writefln("Default Capture Device is '%s'", defaultCaptureDevice.fromStringz);

	CaptureDevice device;
	if (device.open(defaultCaptureDevice, frequency, BufferFormat.MONO_FLOAT, deviceBufferSize))
	{
		writefln("Opened '%s' Capture Device", device.name);
		writefln("device buffer %s, user buffer %s", deviceBufferSize, consumerBuffer.length);
		device.startCapture;

		bool consumerRunning = true;
		while (consumerRunning)
		{
			if (delayMsecs > 0)
				Thread.sleep(delayMsecs.msecs);

			if (device.samplesAvailable >= consumerBuffer.length)
			{
				device.captureSamples(consumerBuffer);
				consumerRunning = dataConsumer(consumerBuffer);
			}
		}

		device.stopCapture;
		device.close;
	}
}

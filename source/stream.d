module stream;

import audio;

struct StreamParams
{
	size_t freq = 44_100;
	size_t numBuffers = 3;
	size_t bufferLength = 512;
	size_t totalSamples;
	size_t sleepMsecs;
}

void playGeneratedStream(StreamParams params,
	float delegate(size_t t) sampleGenerator)
{
	float[] sampleBuffer = new float[params.bufferLength];
	size_t t;
	Source source;
	source.init();
	scope(exit) source.release();

	// returns null after params.totalSamples generated
	float[] generator()
	{
		size_t numSamples = params.bufferLength;
		if (t + params.bufferLength > params.totalSamples)
			numSamples = params.totalSamples - t;

		foreach(ref sample; sampleBuffer[0..numSamples])
		{
			sample = sampleGenerator(t);
			++t;
		}
		return sampleBuffer[0..numSamples];
	}

    playStream(source, params.numBuffers, params.freq, params.sleepMsecs, &generator);
}

// Stream player function.
// Fills buffers first and then loops
// and fills used buffers to keep stream playing.
void playStream(
	ref Source source, size_t numBuffers,
	size_t frequency, size_t delayMsecs,
	float[] delegate() dataProvider)
{
	import core.thread;

	Buffer[] streamBuffers = new Buffer[numBuffers];
	streamBuffers.init();

	float[] sampleBuffer;

	// Detach previous sound.
	source.detachBuffer();

	bool done;
	// Buffer fill function.
	void queueBuffer(Buffer bufferToFill)
	{
		sampleBuffer = dataProvider();
		if (sampleBuffer.length == 0) {
			done = true;
			return;
		}

		// Load data into buffer
		bufferToFill.loadData(BufferFormat.MONO_FLOAT,
			cast(ubyte[])sampleBuffer, frequency);
		source.queueBuffer(bufferToFill);
	}

	foreach(buffer; streamBuffers) {
		queueBuffer(buffer);
	}

	// Play sound
	source.play();
	scope(exit) {
		// Stop sound if user presses enter
		source.stop();
		source.detachBuffer();
		streamBuffers.release();
	}

	Buffer[] buffers = new Buffer[numBuffers];
	while(true)
	{
		if (delayMsecs > 0)
			Thread.sleep(delayMsecs.msecs);

		Buffer[] processedBuffers = source.unqueueProcessedBuffers(buffers);

		foreach(buffer; processedBuffers)
		{
			queueBuffer(buffer);
		}

		if(source.state != SourceState.playing) {
			if (done)
				break;
			else
				source.play();
		}
	}
}

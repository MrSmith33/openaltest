/**
Copyright: Copyright (c) 2015-2016 Andrey Penechko.
License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Andrey Penechko.
*/
module synth;

struct SampleGenerator(float delegate(size_t) generator)
{
	size_t t;

	float next() {
		float sample = generator(t);
		++t;
		return sample;
	}
}

struct DynSampleGenerator
{
	float delegate(size_t) generator;
	size_t t;

	float next() {
		float sample = generator(t);
		++t;
		return sample;
	}
}

// sound generation


float sin(size_t sampleRate, float sinFrequency)(size_t t)
{
	import std.math : sin, PI;
	return sin(t * 2.0 * PI * sinFrequency / sampleRate);
}

float fadeIn(size_t sampleRate, float speed)(ptrdiff_t t)
{
	if (t > 0)
		return 1.0;
	else
	{
		float x = cast(float)t / sampleRate;
		return speed^^x;
	}
}

float fadeOut(size_t sampleRate, float speed)(ptrdiff_t t)
{
	if (t < 0)
		return 1.0;
	else
	{
		float x = cast(float)t / sampleRate;
		return 1.0/(speed^^x);
	}
}

module audioengine;

import std.conv;
import std.datetime.stopwatch;
import std.stdio;
import std.string;

import soundio.soundio;

enum MINIMP3_MAX_SAMPLES_PER_FRAME = 1152 * 2;

extern (C)
{
	struct mp3dec_frame_info_t
	{
		int frame_bytes;
		int channels;
		int hz;
		int layer;
		int bitrate_kbps;
	}

	struct mp3dec_t
	{
		float[9 * 32][2] mdct_overlap;
		float[15 * 2 * 32] qmf_state;
		int reserv;
		int free_format_bytes;
		ubyte[4] header;
		ubyte[511] reserv_buf;
	}

	void mp3dec_init(mp3dec_t* dec);
	int mp3dec_decode_frame(mp3dec_t* dec, const ubyte* mp3, int mp3_bytes,
			ref short[MINIMP3_MAX_SAMPLES_PER_FRAME] pcm, mp3dec_frame_info_t* info);
}

__gshared AudioEngine audio;

struct SoundEffect
{
	short[] data;
	ptrdiff_t time;
	float volume = 1;

	string toString() const
	{
		return "SoundEffect(" ~ time.to!string ~ " / " ~ data.length.to!string ~ ")";
	}
}

/// Represents the audio engine to play music accurately. There should be only one instance of this.
struct AudioEngine
{
	/// Raw stereo data to use for playing.
	short[] audioData;
	/// Current audio sample rate.
	int audioSampleRate;
	/// Index where the audio stream is currently at.
	ptrdiff_t audioReadIndex;
	SoundEffect[16] playingEffects;

	/// Device to handle sound device management with.
	SoundIo* soundio;
	/// Device to play sound to.
	SoundIoDevice* device;
	/// Stream to use for playing.
	SoundIoOutStream* outstream;
	/// Channel count the outstream is created for.
	int outstreamCreatedFor;
	/// Sample rate the outstream is created for.
	int outstreamCreatedForHz;
	/// true only after successful load initializing everything.
	bool success;
	/// Error code filled by mpg123.
	int mpgError;

	/// Current chunk start milliseconds in the music.
	int currentMsecs;
	/// Current offset in the chunk (running alongside actual audio).
	StopWatch currentOffset;
	/// Playback speed.
	float speed = 1;
	/// Speed when last sent a frame.
	float effectiveSpeed = 1;
	/// Master sound volume
	float masterVolume = 1;
	/// Background music volume
	float musicVolume = 1;
	/// Master sound effect volume
	float effectsVolume = 1;
	/// Background music offset
	Duration offset = -30.msecs;

	/// minimp3 instance for mp3 decoding
	mp3dec_t decoder;
	/// True if play has been called.
	bool playing;

	@disable this(this);

	/// Initializes the sound device and prepares for playing.
	void load()
	{
		if (success)
			throw new Exception("Attempted to load same audio engine twice.");

		soundio = soundio_create();
		if (!soundio)
		{
			stderr.writeln("Out of memory trying to allocate soundio.");
			assert(false);
		}

		if (auto err = soundio_connect(soundio))
		{
			stderr.writeln("Error connecting audio device: ", soundio_strerror(err).fromStringz);
			return;
		}

		soundio_flush_events(soundio);

		int default_out_device_index = soundio_default_output_device_index(soundio);
		if (default_out_device_index < 0)
		{
			stderr.writeln("No output device found");
			return;
		}

		device = soundio_get_output_device(soundio, default_out_device_index);
		if (!device)
		{
			stderr.writeln("Failed to get output device");
			return;
		}

		stderr.writeln("Using audio device ", device.name.fromStringz);

		mp3dec_init(&decoder);

		audioReadIndex = 0;
		success = true;
	}

	~this()
	{
		if (outstream)
		{
			soundio_outstream_destroy(outstream);
			outstream = null;
		}
		if (device)
		{
			soundio_device_unref(device);
			device = null;
		}
		if (soundio)
		{
			soundio_destroy(soundio);
			soundio = null;
		}
		success = false;
	}

	bool createOutstream(int channels, int hz)
	{
		if (outstreamCreatedFor == channels && outstreamCreatedForHz == hz)
			return true;

		if (outstream)
			soundio_outstream_destroy(outstream);

		outstream = soundio_outstream_create(device);
		outstream.format = SoundIoFormatS16NE;
		outstream.sample_rate = hz;
		outstream.software_latency = 0.03; // should be a bit higher for recordings to work, but low enough not to introduce any input delay, around 30ms is good.
	ChannelSelect:
		switch (channels)
		{
			static foreach (supported_channels; 1 .. 3)
			{
		case supported_channels:
				outstream.write_callback = &writeCallback!supported_channels;
				break ChannelSelect;
			}
		default:
			stderr.writeln("Unsupported channel count: ", channels);
			return false;
		}

		if (auto err = soundio_outstream_open(outstream))
		{
			stderr.writeln("Unable to open device: ", soundio_strerror(err).fromStringz);
			return false;
		}

		if (outstream.layout_error)
			stderr.writeln("Unable to set channel layout: ",
					soundio_strerror(outstream.layout_error).fromStringz);

		return true;
	}

	void play(in ubyte[] mp3data, bool autoStart = true)
	{
		short[MINIMP3_MAX_SAMPLES_PER_FRAME] pcm;
		mp3dec_frame_info_t info;
		auto samples = mp3dec_decode_frame(&decoder, mp3data.ptr,
				cast(int) mp3data.length, pcm, &info);

		auto channelCount = info.channels;
		audioSampleRate = info.hz;
		if (!createOutstream(channelCount, info.hz))
		{
			writeln("Failed to create outstream");
			return;
		}

		int offset;

		while (info.frame_bytes > 0)
		{
			offset += info.frame_bytes;
			assert(info.channels == channelCount);
			assert(info.hz == audioSampleRate);
			if (samples > 0)
			{
				audioData ~= pcm[0 .. samples * channelCount];
			}
			samples = mp3dec_decode_frame(&decoder, mp3data.ptr + offset,
					cast(int) mp3data.length - offset, pcm, &info);
		}

		playing = true;
		if (autoStart)
			resume();
	}

	void tick()
	{
		soundio_flush_events(soundio);
	}

	void wait()
	{
		soundio_wait_events(soundio);
	}

	void reset()
	{
		audioReadIndex = 0;
	}

	void resume()
	{
		if (!playing)
			return;
		if (!success)
			throw new Exception("Attempted to resume unsuccessful audio engine.");
		if (!outstream)
			throw new Exception("Outstream not initialized");
		outstream.userdata = &this;
		if (auto err = soundio_outstream_start(outstream))
		{
			stderr.writeln("Unable to start device: ", soundio_strerror(err).fromStringz);
			return;
		}
		currentOffset.start();
	}

	void stop(bool pause)
	{
		if (!playing)
			return;
		if (!success)
			throw new Exception("Attempted to resume unsuccessful audio engine.");
		soundio_outstream_pause(outstream, pause);
		currentOffset.stop();
	}

	void clearBuffer()
	{
		soundio_outstream_clear_buffer(outstream);
	}

	Duration currentTime()
	{
		return currentMsecs.msecs + (cast(long)(currentOffset.peek.total!"hnsecs" * effectiveSpeed))
			.hnsecs + offset;
	}

	void playEffect(SoundEffect effect)
	{
		size_t max = 0;
		ptrdiff_t maxLen = 0;
		foreach (i, ref sound; playingEffects)
		{
			if (sound.time >= sound.data.length || sound.time > maxLen)
			{
				max = i;
				maxLen = sound.time;
				if (sound.time >= sound.data.length)
					break;
			}
		}
		playingEffects[max] = effect;
		playingEffects[max].time = 0;
	}

	extern (C) static void writeCallback(int channels)(SoundIoOutStream* outstream,
			int frame_count_min, int frame_count_max)
	{
		const SoundIoChannelLayout* layout = &outstream.layout;
		float float_sample_rate = outstream.sample_rate;
		float seconds_per_frame = 1.0f / float_sample_rate;
		SoundIoChannelArea* areas;
		int frames_left = frame_count_max;

		AudioEngine* instance = cast(AudioEngine*) outstream.userdata;

		while (frames_left > 0)
		{
			int frame_count = frames_left;

			if (auto err = soundio_outstream_begin_write(outstream, &areas, &frame_count))
			{
				stderr.writeln(soundio_strerror(err).fromStringz);
				return;
			}

			if (!frame_count)
				break;

			float step = 1;
			if (instance.audioSampleRate != outstream.sample_rate)
				step = instance.audioSampleRate / float_sample_rate;
			auto framesRead = frame_count;

			foreach (frame; 0 .. frame_count)
			{
				auto readFrame = cast(int)(frame * instance.speed);
				if ((instance.audioReadIndex + cast(ptrdiff_t) readFrame) * channels + channels > cast(
						ptrdiff_t) instance.audioData.length)
					break;
				int effect;
				foreach (ref sound; instance.playingEffects)
				{
					if (sound.time < sound.data.length)
					{
						if (sound.time >= 0)
							effect += cast(short)(sound.data.ptr[sound.time] * sound.volume);
						sound.time++;
					}
				}
				effect = cast(int)(effect * instance.effectsVolume);
				short[channels] sample = void;
				if (instance.audioReadIndex < 0)
					sample[] = 0;
				else if (instance.audioSampleRate == outstream.sample_rate)
				{
					static foreach (i; 0 .. channels)
						sample[i] = instance.audioData.ptr[(instance.audioReadIndex + readFrame) * channels + i];
				}
				else
				{
					auto offset = cast(int)(frame * instance.speed * step * channels);
					static foreach (i; 0 .. channels)
						sample[i] = instance.audioData.ptr[instance.audioReadIndex * channels + offset + i];
				}
				foreach (channel; 0 .. layout.channel_count)
				{
					short* ptr = cast(short*)(areas[channel].ptr + areas[channel].step * frame);
					int tmp = cast(int)((cast(int)(
							sample[channel % channels] * instance.musicVolume) + effect) * instance.masterVolume);
					if (tmp > short.max)
						*ptr = short.max;
					else if (tmp < short.min)
						*ptr = short.min;
					else
						*ptr = cast(short) tmp;
				}
			}
			instance.audioReadIndex += cast(int)(frame_count * instance.speed);

			instance.currentMsecs = cast(int)(
					instance.audioReadIndex / cast(float) instance.audioSampleRate * 1000);
			instance.currentOffset.reset();
			instance.effectiveSpeed = instance.speed;

			if (auto err = soundio_outstream_end_write(outstream))
			{
				if (err == SoundIoError.SoundIoErrorUnderflow)
					return;
				stderr.writeln(soundio_strerror(err).fromStringz);
				return;
			}

			frames_left -= frame_count;
		}
	}
}

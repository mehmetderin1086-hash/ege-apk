"""Explicit download profiles and iPhone-compatible highest-quality conversion."""
import math

QUALITIES = {"standard", "highest"}


def download_options(format, quality):
    if format == "mp3":
        # Do not prefer AAC over a higher quality Opus source before MP3 encoding.
        return "bestaudio/best", "abr,asr,acodec" if quality == "highest" else "res:1080,vcodec:h264,acodec:aac"
    if quality == "standard":
        return "bestvideo[height<=1080]+bestaudio/best[height<=1080]", "res:1080,vcodec:h264,acodec:aac"
    # Both landscape and portrait fit. Actual dimensions and transfer function
    # are checked after download; no source is upscaled to claim 4K.
    filters = "[width<=3840][height<=3840][fps<=?60][dynamic_range=?SDR]"
    return "bestvideo" + filters + "+bestaudio/best" + filters, "res:2160,fps,vcodec:h264,abr,asr"


def first_stream(probe, kind):
    return next((item for item in probe.get("streams", [])
                 if item.get("codec_type") == kind and not item.get("disposition", {}).get("attached_pic")), None)


def positive_int(value):
    try:
        number = float(value)
        return int(number) if math.isfinite(number) and number > 0 else None
    except (ValueError, TypeError, OverflowError):
        return None


def media_info(probe):
    audio, video = first_stream(probe, "audio"), first_stream(probe, "video")
    result = {}
    if audio:
        result.update(audio_codec=audio.get("codec_name"), audio_bitrate=positive_int(audio.get("bit_rate")),
                      sample_rate=positive_int(audio.get("sample_rate")))
    if video:
        result.update(video_codec=video.get("codec_name"), width=positive_int(video.get("width")),
                      height=positive_int(video.get("height")))
    return {key: value for key, value in result.items() if value is not None}


def frame_rate(stream):
    for key in ("avg_frame_rate", "r_frame_rate"):
        try:
            text = str(stream.get(key, "0"))
            numerator, denominator = text.split("/") if "/" in text else (text, "1")
            value = float(numerator) / float(denominator)
            if math.isfinite(value) and value > 0:
                return value
        except (ValueError, ZeroDivisionError, OverflowError):
            continue
    return None


def conversion_options(format, quality, probe=None):
    if format == "mp3":
        options = ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-b:a",
                   "320k" if quality == "highest" else "192k", "-id3v2_version", "3"]
        if quality == "highest":
            audio = first_stream(probe or {}, "audio")
            if not audio:
                raise RuntimeError("İndirilen kaynakta ses kanalı bulunamadı.")
            options += ["-ac", "2"]
            # MPEG-1 sample rates support 320 kbit/s; retain the source rate
            # whenever possible instead of unnecessarily resampling it.
            if positive_int(audio.get("sample_rate")) not in {32000, 44100, 48000}:
                options += ["-ar", "48000"]
        return options
    if quality == "standard":
        return ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
                "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]
    video = first_stream(probe or {}, "video")
    audio = first_stream(probe or {}, "audio")
    if not video:
        raise RuntimeError("İndirilen kaynakta video kanalı bulunamadı.")
    width, height = positive_int(video.get("width")), positive_int(video.get("height"))
    if not width or not height:
        raise RuntimeError("Videonun gerçek çözünürlüğü doğrulanamadı.")
    fps = frame_rate(video)
    if fps is None:
        raise RuntimeError("Videonun kare hızı doğrulanamadı.")
    # A hidden HDR source must never be decoded as ordinary SDR. YouTube
    # normally offers an SDR rendition, which is selected above.
    if video.get("color_transfer") in {"smpte2084", "arib-std-b67"} or video.get("color_primaries") == "bt2020":
        raise RuntimeError("Bu kaynak HDR. Renkleri korumak için SDR sürümü olan bir video seçin.")
    fits = max(width, height) <= 3840 and min(width, height) <= 2160 and width % 2 == height % 2 == 0
    copy_video = (video.get("codec_name") == "h264" and video.get("pix_fmt") in {"yuv420p", "yuvj420p"}
                  and video.get("profile") in {"High", "Main", "Baseline", "Constrained Baseline"}
                  and (positive_int(video.get("level")) or 100) <= 52 and fits and fps <= 60.01)
    options = ["-map", "0:v:0", "-map", "0:a:0?"]
    if copy_video:
        options += ["-c:v", "copy"]
    else:
        scale = ("scale=w='if(gte(iw,ih),min(3840,iw),min(2160,iw))':"
                 "h='if(gte(iw,ih),min(2160,ih),min(3840,ih))':"
                 "force_original_aspect_ratio=decrease:force_divisible_by=2")
        if fps > 60.01:
            scale += ",fps=60"
        options += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
                    "-pix_fmt", "yuv420p", "-vf", scale]
    if audio and audio.get("codec_name") == "aac" and audio.get("profile") == "LC" and (positive_int(audio.get("channels")) or 99) <= 2:
        options += ["-c:a", "copy"]
    else:
        options += ["-c:a", "aac", "-b:a", "320k", "-ac", "2"]
    return options + ["-movflags", "+faststart"]

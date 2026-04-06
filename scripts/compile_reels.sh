#!/bin/bash
set -e
set -x

TMP="./tmp/hiddenmemoriz/reelclips"
OUTPUT="./hiddenmemoriz/output/final_merged.mp4"
INPUT_DIR="./hiddenmemoriz/reels"
AUDIO_DIR="./hiddenmemoriz/audio"

mkdir -p "$TMP"
mkdir -p "$(dirname "$OUTPUT")"

# pick 15 random mp4s
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
[ ${#FILES[@]} -eq 0 ] && echo "❌ No .mp4 files found" && exit 1

# pick 1 random audio
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)
[ -z "$AUDIO_FILE" ] && echo "❌ No audio file found" && exit 1
echo "🎵 Using audio: $AUDIO_FILE"

i=1
for f in "${FILES[@]}"; do
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  LENGTH=2
  START=$(awk -v d="$DURATION" 'BEGIN{srand(); if(d>LENGTH) printf "%.3f", rand()*(d-LENGTH); else print 0}')
  ffmpeg -ss "$START" -i "$f" -t "$LENGTH" \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
    -an "$TMP/clip_$i.mp4" -y -loglevel error

  [ -f "$TMP/clip_$i.mp4" ] && echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

[ ! -s "$TMP/list.txt" ] && echo "❌ No clips created" && exit 1

# merge clips
MERGED_TMP="$TMP/merged.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$MERGED_TMP" -y -loglevel error

# add audio with fade-out
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_TMP")
ffmpeg -i "$MERGED_TMP" -i "$AUDIO_FILE" \
  -filter_complex "[1:a]afade=t=out:st=$(awk -v d="$VIDEO_DURATION" 'BEGIN{print d-2}') :d=2[aud]" \
  -map 0:v -map "[aud]" -c:v copy -c:a aac -shortest "$OUTPUT" -y -loglevel error

echo "🎬 Done — created $OUTPUT"

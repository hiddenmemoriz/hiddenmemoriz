#!/bin/bash
set -e

# Directories & files
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
FONT="./Inter-Black.ttf"
LOGO_PATH="./spotify.png"
QUOTES_FILE="./quotes.txt"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

# Check input files
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
[ ${#FILES[@]} -eq 0 ] && echo "❌ No .mp4 files found in $INPUT_DIR." && exit 1

AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)
[ -z "$AUDIO_FILE" ] && echo "❌ No audio file found in $AUDIO_DIR." && exit 1
echo "🎵 Using audio: $AUDIO_FILE"

[ ! -f "$QUOTES_FILE" ] && echo "❌ quotes.txt not found" && exit 1
[ ! -f "$LOGO_PATH" ] && echo "❌ spotify.png not found" && exit 1
TOTAL=$(wc -l < "$QUOTES_FILE")
[ "$TOTAL" -eq 0 ] && echo "❌ quotes.txt is empty" && exit 1

# Process video clips
i=1
for f in "${FILES[@]}"; do
  echo "➡️ Processing: $f"
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  LENGTH=1
  START=$(awk -v d="$DURATION" 'BEGIN{srand(); if(d>1) printf "%.3f", rand()*(d-1); else print 0}')

  ffmpeg -ss "$START" -i "$f" -t "$LENGTH" \
    -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30" \
    -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
    -an "$TMP/clip_$i.mp4" -y -loglevel error

  [ -f "$TMP/clip_$i.mp4" ] && echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

[ ! -s "$TMP/list.txt" ] && echo "❌ No clips created." && rm -rf "$TMP" && exit 1

# Merge clips
MERGED_TMP="$TMP/merged.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -c copy "$MERGED_TMP" -y -loglevel error
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_TMP")

# Add audio with safe fade-out
FADE_START=$(awk -v d="$VIDEO_DURATION" 'BEGIN{print (d>2)?d-2:0}')
MERGED_AUDIO="$TMP/merged_audio.mp4"
ffmpeg -i "$MERGED_TMP" -i "$AUDIO_FILE" \
  -filter_complex "[1:a]afade=t=out:st=$FADE_START:d=2[aud]" \
  -map 0:v -map "[aud]" -c:v copy -c:a aac -shortest "$MERGED_AUDIO" -y -loglevel error

# Pick random quote
line=$((RANDOM % TOTAL + 1))
raw=$(sed -n "${line}p" "$QUOTES_FILE")
wrapped=$(echo "$raw" | fold -s -w 40 | awk 'NF>0{$1=$1;print}')

# Escape text for ffmpeg drawtext
escaped=$(echo "$wrapped" | sed "s/'/\\'/g" | sed 's/[:]/_/g' | sed 's/[,]/_/g' | awk '{printf "%s\\n",$0}' | sed 's/\\n$//')

# Generate safe output file name (keep full quote)
safe=$(echo "$raw" | sed 's/[^a-zA-Z0-9 _-]/_/g')
out="$OUTPUT_DIR/${safe}.mp4"
[ -e "$out" ] && out="$OUTPUT_DIR/${safe}_$(date +%s).mp4"

# Prepare ffmpeg filter for logo + text
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_AUDIO")
logo_start=$(awk -v d="$duration" 'BEGIN{printf "%.2f", d/2}')
logo_end=$(awk -v d="$duration" 'BEGIN{printf "%.2f", d-1}')
logo_fadeout=$(awk -v e="$logo_end" 'BEGIN{printf "%.2f", e-1}')

FILTER="[1:v]loop=loop=-1:size=1:start=0,fps=30,setpts=N/(30*TB),scale=200:-1,format=rgba,fade=t=in:st=${logo_start}:d=1:alpha=1,fade=t=out:st=${logo_fadeout}:d=1:alpha=1[logo]; \
[0:v][logo]overlay=x=(W-w)/2:y=H-h-50:format=auto:shortest=1,format=rgba[v_logo]; \
[v_logo]drawtext=fontfile='${FONT}':text='${escaped}':fontcolor=white:fontsize=35:box=1:boxcolor=black@0.7:boxborderw=10:line_spacing=10:x=(w-text_w)/2:y=(h*0.25)[v_out]"

# Render final video
ffmpeg -i "$MERGED_AUDIO" -i "$LOGO_PATH" \
  -filter_complex "$FILTER" \
  -map "[v_out]" -map 0:a \
  -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -c:a copy \
  -shortest "$out" -y -loglevel warning

echo "🎬 Done — final output: $out"

# Clean temp
rm -rf "$TMP"

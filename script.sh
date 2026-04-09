#!/bin/bash
set -e

# Directories
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
LOGO_PATH="./spotify.png"
QUOTES_FILE="./quotes.txt"
OUTPUT_DIR="./output"
# Using your original font
ORIGINAL_FONT="./Inter-Black.ttf"

mkdir -p "$OUTPUT_DIR"

# 1. PREPARE ASSETS
# Use original font if exists, otherwise fallback to system font to prevent crash
if [ -f "$ORIGINAL_FONT" ]; then
    FONT_PATH="$ORIGINAL_FONT"
else
    echo "⚠️ Original font not found, using system fallback"
    FONT_PATH="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
fi

sed -i 's/\r//' "$QUOTES_FILE"

# 2. SELECT RANDOM ASSETS
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)

# 3. PROCESS CLIPS
i=1
for f in "${FILES[@]}"; do
  ffmpeg -i "$f" -t 1 -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:trunc((ow-iw)/2):trunc((oh-ih)/2):black,fps=30" \
    -c:v libx264 -preset superfast -an "$TMP/clip_$i.mp4" -y -loglevel error
  echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

# 4. MERGE CLIPS & ADD AUDIO
MERGED_AUDIO="$TMP/merged_audio.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -i "$AUDIO_FILE" \
  -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest "$MERGED_AUDIO" -y -loglevel error

VIDEO_DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MERGED_AUDIO")

# 5. QUOTE FORMATTING
RAW_QUOTE=$(shuf -n 1 "$QUOTES_FILE")
# Wrapped at 35 characters for a cleaner look at the top
echo "$RAW_QUOTE" | fold -s -w 35 > "$TMP/final_text.txt"

SAFE_NAME=$(echo "$RAW_QUOTE" | sed 's/[^a-zA-Z0-9 ]/ /g' | tr -s ' ' | cut -c1-50 | xargs)
FINAL_OUT="$OUTPUT_DIR/${SAFE_NAME}.mp4"

# 6. LOGO & TEXT TIMING
logo_start=$(awk -v d="$VIDEO_DUR" 'BEGIN{printf "%.2f", d/2}')
logo_fade=$(awk -v d="$VIDEO_DUR" 'BEGIN{printf "%.2f", d-1}')

# 7. THE FILTER
# - Text y=(h*0.15): Places text at 15% from the top
# - Text fontsize=40: Smaller as requested
# - Logo: Positioned near the bottom
FILTER="[1:v]scale=200:-1,format=rgba,fade=t=in:st=${logo_start}:d=1:alpha=1,fade=t=out:st=${logo_fade}:d=1:alpha=1[logo]; \
[0:v][logo]overlay=x=(W-w)/2:y=H-h-200[v_logo]; \
[v_logo]drawtext=fontfile='${FONT_PATH}':textfile='$TMP/final_text.txt':fontcolor=white:fontsize=40: \
box=1:boxcolor=black@0.7:boxborderw=15:line_spacing=10:x=(w-text_w)/2:y=(h*0.15)"

# 8. FINAL RENDER
ffmpeg -i "$MERGED_AUDIO" -i "$LOGO_PATH" \
  -filter_complex "$FILTER" \
  -c:v libx264 -preset fast -crf 22 -c:a copy -movflags +faststart "$FINAL_OUT" -y

echo "🎬 Output created: $FINAL_OUT"

# Clean up
rm -rf "$TMP"

#!/bin/bash
set -e

# Directories
TMP=$(mktemp -d)
INPUT_DIR="./reels"
AUDIO_DIR="./audio"
LOGO_PATH="./spotify.png"
QUOTES_FILE="./quotes.txt"
OUTPUT_DIR="./output"

mkdir -p "$OUTPUT_DIR"

# 1. FIX: Copy system font to local dir to guarantee accessibility
LOCAL_FONT="$TMP/font.ttf"
cp /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf "$LOCAL_FONT"

# 2. Select random assets
FILES=($(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.mp4" | sort -R | head -n 15))
AUDIO_FILE=$(find "$AUDIO_DIR" -maxdepth 1 -type f -iname "*.mp3" | sort -R | head -n 1)

# 3. Process clips (1080x1920)
i=1
for f in "${FILES[@]}"; do
  ffmpeg -i "$f" -t 1 -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black,fps=30" \
    -c:v libx264 -preset superfast -an "$TMP/clip_$i.mp4" -y -loglevel error
  echo "file '$TMP/clip_$i.mp4'" >> "$TMP/list.txt"
  i=$((i+1))
done

# 4. Merge
MERGED_AUDIO="$TMP/merged_audio.mp4"
ffmpeg -f concat -safe 0 -i "$TMP/list.txt" -i "$AUDIO_FILE" -c:v copy -c:a aac -shortest "$MERGED_AUDIO" -y -loglevel error

# 5. Quote Formatting (The "Fix")
RAW_QUOTE=$(shuf -n 1 "$QUOTES_FILE")
# Wrap text and replace literal newlines with FFmpeg-friendly escaped newlines
# We use 'sed' to turn actual newlines into the string '\n'
WRAPPED_TEXT=$(echo "$RAW_QUOTE" | fold -s -w 30 | sed ':a;N;$!ba;s/\n/\\n/g' | sed "s/'/\\\\'/g")

# Clean filename
SAFE_NAME=$(echo "$RAW_QUOTE" | sed 's/[^a-zA-Z0-9 ]/ /g' | tr -s ' ' | cut -c1-50 | xargs)
FINAL_OUT="$OUTPUT_DIR/${SAFE_NAME}.mp4"

# 6. The Filter (Redesigned for compatibility)
# - Using the local font path
# - Using the direct text string instead of textfile
# - Simplified box logic
FILTER="[1:v]scale=200:-1,format=rgba,fade=t=in:st=2:d=1:alpha=1,fade=t=out:st=13:d=1:alpha=1[logo]; \
[0:v][logo]overlay=x=(W-w)/2:y=H-h-150[v_logo]; \
[v_logo]drawtext=fontfile='${LOCAL_FONT}':text='${WRAPPED_TEXT}':fontcolor=white:fontsize=50: \
box=1:boxcolor=black@0.6:boxborderw=20:line_spacing=10:x=(w-text_w)/2:y=(h-text_h)/2"

# 7. Final Render
ffmpeg -i "$MERGED_AUDIO" -i "$LOGO_PATH" \
  -filter_complex "$FILTER" \
  -c:v libx264 -preset fast -crf 22 -c:a copy -movflags +faststart "$FINAL_OUT" -y

echo "🎬 Output created: $FINAL_OUT"
rm -rf "$TMP"

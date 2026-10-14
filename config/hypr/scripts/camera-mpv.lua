-- camera-mpv.lua — in-window photo/recording keys for the webcam preview.
--
-- Loaded by camera.sh (`mpv --script=...`). mpv owns the V4L2 device, so the
-- photo and the recording are driven from here to respect the single-reader
-- limitation of the webcam:
--   s  take a photo (mpv screenshot)      -> CAMERA_PHOTO_DIR
--   r  start/stop a recording             -> CAMERA_VIDEO_DIR
--
-- A recording is remuxed by mpv to a FIFO (Matroska/MJPEG) and a background
-- ffmpeg re-encodes it to H.264 MP4, keeping the file small.

local HOME = os.getenv("HOME") or ""
local PHOTO_DIR = os.getenv("CAMERA_PHOTO_DIR") or (HOME .. "/Imágenes/Camera")
local VIDEO_DIR = os.getenv("CAMERA_VIDEO_DIR") or (HOME .. "/Vídeos/Camera")
local FIFO = os.getenv("CAMERA_STREAM_FIFO") or "/tmp/osu-cam-stream.mkv"
local LOG = "/tmp/osu-cam-rec.log"
local PIDFILE = "/tmp/osu-cam-ffmpeg.pid"

local function sh(cmd) os.execute(cmd) end
local function q(s) return "'" .. s .. "'" end
local function osd(m) mp.osd_message(m, 3) end

local function is_recording()
    local v = mp.get_property("stream-record")
    return v ~= nil and v ~= ""
end

local function take_photo()
    sh("mkdir -p " .. q(PHOTO_DIR))
    mp.command("screenshot")
    osd("Foto guardada -> " .. PHOTO_DIR .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".jpg")
end

local function start_recording()
    sh("mkdir -p " .. q(VIDEO_DIR))
    local out = VIDEO_DIR .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".mp4"
    sh("rm -f " .. q(FIFO) .. "; mkfifo " .. q(FIFO))
    sh("ffmpeg -hide_banner -loglevel error -f matroska -i " .. q(FIFO) ..
       " -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -y " .. q(out) ..
       " >" .. LOG .. " 2>&1 & echo $! > " .. PIDFILE)
    mp.set_property("stream-record", FIFO)
    osd("Grabando -> " .. out)
end

local function stop_recording()
    mp.set_property("stream-record", "")
    osd("Grabación guardada en " .. VIDEO_DIR)
end

mp.add_key_binding("s", "camera-photo", take_photo)
mp.add_key_binding("r", "camera-record", function()
    if is_recording() then
        stop_recording()
    else
        start_recording()
    end
end)

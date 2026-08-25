"""Camera app logic: photo/video capture from the MacBook's front camera."""

import datetime
import time
import tkinter as tk
from pathlib import Path

import cv2
from PIL import Image, ImageDraw, ImageTk

SAVE_DIR = Path(__file__).resolve().parent.parent
FPS = 30
PREVIEW_WIDTH = 720  # cap preview width so the window always fits on screen


def camera_icon(size=64):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((size * .08, size * .28, size * .92, size * .86), radius=size * .08, fill=(45, 45, 48))
    r = size * .2
    cx, cy = size * .5, size * .56
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(20, 20, 22), outline=(200, 200, 200), width=2)
    r *= .5
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(90, 150, 220))
    return img


def record_icon(size=48, active=False):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((0, 0, size, size), outline=(60, 60, 60), width=2)
    pad = size * (.32 if active else .18)
    box = (pad, pad, size - pad, size - pad)
    if active:
        draw.rounded_rectangle(box, radius=size * .06, fill=(220, 40, 40))
    else:
        draw.ellipse(box, fill=(220, 40, 40))
    return img


class CameraApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Camera")
        self.icon = ImageTk.PhotoImage(camera_icon(128))
        self.root.iconphoto(True, self.icon)

        self.cap = cv2.VideoCapture(0)
        if not self.cap.isOpened():
            raise RuntimeError("Could not open the camera")
        self.writer = None
        self.recording = False
        self.current_frame = None

        self.video_label = tk.Label(root)
        self.video_label.pack()

        buttons = tk.Frame(root)
        buttons.pack(pady=8)
        self.photo_icon = ImageTk.PhotoImage(camera_icon())
        self.rec_icon = ImageTk.PhotoImage(record_icon())
        self.stop_icon = ImageTk.PhotoImage(record_icon(active=True))

        self.photo_btn = self._button(buttons, self.photo_icon, "Photo", self.take_photo)
        self.record_btn = self._button(buttons, self.rec_icon, "Start Recording", self.toggle_recording)

        self.status_label = tk.Label(root, text="Space — take a photo")
        self.status_label.pack()

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.bind("<space>", lambda e: self.take_photo())
        self.update_frame()
        self.root.update_idletasks()
        self.root.eval("tk::PlaceWindow . center")

    @staticmethod
    def _button(parent, image, text, command):
        btn = tk.Button(parent, image=image, text=text, compound=tk.TOP,
                         command=command, relief=tk.FLAT, width=90, height=70)
        btn.pack(side=tk.LEFT, padx=15)
        return btn

    def timestamp(self):
        return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    def update_frame(self):
        ok, frame = self.cap.read()
        if ok:
            self.current_frame = frame
            if self.recording and self.writer is not None:
                # write frames by elapsed wall-clock time, duplicating if the
                # capture loop falls behind FPS, so playback speed stays correct
                target = int((time.monotonic() - self.record_start) * FPS)
                while self.frames_written < target:
                    self.writer.write(frame)
                    self.frames_written += 1

            h, w = frame.shape[:2]
            preview = frame
            if w > PREVIEW_WIDTH:
                scale = PREVIEW_WIDTH / w
                preview = cv2.resize(frame, (int(w * scale), int(h * scale)))

            rgb = cv2.cvtColor(preview, cv2.COLOR_BGR2RGB)
            imgtk = ImageTk.PhotoImage(Image.fromarray(rgb))
            self.video_label.imgtk = imgtk
            self.video_label.configure(image=imgtk)

        self.root.after(int(1000 / FPS), self.update_frame)

    def take_photo(self):
        if self.current_frame is None:
            return
        path = SAVE_DIR / f"photo_{self.timestamp()}.jpg"
        cv2.imwrite(str(path), self.current_frame)
        self.status_label.config(text=f"Photo saved: {path.name}")

    def toggle_recording(self):
        if not self.recording:
            height, width = self.current_frame.shape[:2]
            path = SAVE_DIR / f"video_{self.timestamp()}.mp4"
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            self.writer = cv2.VideoWriter(str(path), fourcc, FPS, (width, height))
            self.record_start = time.monotonic()
            self.frames_written = 0
            self.recording = True
            self.record_btn.config(image=self.stop_icon, text="Stop")
            self.status_label.config(text=f"Recording: {path.name}")
        else:
            self.recording = False
            self.writer.release()
            self.writer = None
            self.record_btn.config(image=self.rec_icon, text="Start Recording")
            self.status_label.config(text="Recording saved")

    def on_close(self):
        if self.writer is not None:
            self.writer.release()
        self.cap.release()
        self.root.destroy()

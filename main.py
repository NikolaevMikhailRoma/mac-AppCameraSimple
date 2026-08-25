"""Entry point: launches the camera app."""

import tkinter as tk

from src.camera_app import CameraApp

if __name__ == "__main__":
    root = tk.Tk()
    CameraApp(root)
    root.mainloop()

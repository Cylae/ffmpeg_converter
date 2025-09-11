import tkinter as tk
from tkinter import ttk, filedialog, messagebox, Listbox
import os
import sys
import threading
import queue
import platform
import re

# Add the parent directory to the path to find the core module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from core.ffmpeg_core import FFmpegConverter, FFmpegError

class App(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Advanced Video Converter")
        self.geometry("750x600")
        self.resizable(False, False)

        # --- Core Components & State ---
        self.converter = FFmpegConverter()
        self.progress_queue = queue.Queue()
        self.files_to_convert = []
        self.is_converting = False
        self.available_encoders = []

        # --- UI Variables ---
        self.output_dir = tk.StringVar(value=os.path.expanduser("~"))
        self.video_codec = tk.StringVar(value="H.265 (libx265)")
        self.hw_accel = tk.StringVar(value="None")
        self.quality_mode = tk.StringVar(value="CRF")
        self.quality_value = tk.StringVar(value="23")
        self.audio_codec = tk.StringVar(value="Copy")
        self.shutdown_var = tk.BooleanVar()
        self.status_label_var = tk.StringVar(value="Add files to the queue to begin.")

        # --- UI Construction ---
        self.create_widgets()

        # --- Initial Population & Queue Processing ---
        self.after(100, self.populate_hw_accel)
        self.process_progress_queue()

    def create_widgets(self):
        main_frame = ttk.Frame(self, padding="15")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # --- 1. File Queue ---
        queue_frame = ttk.LabelFrame(main_frame, text="1. File Queue", padding="10")
        queue_frame.pack(fill=tk.BOTH, expand=True, pady=5)

        self.file_listbox = Listbox(queue_frame, selectmode=tk.EXTENDED, height=8)
        self.file_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))

        queue_btn_frame = ttk.Frame(queue_frame)
        queue_btn_frame.pack(side=tk.LEFT, fill=tk.Y)
        ttk.Button(queue_btn_frame, text="Add File(s)", command=self.add_files).pack(fill=tk.X, pady=2)
        ttk.Button(queue_btn_frame, text="Add Folder", command=self.add_folder).pack(fill=tk.X, pady=2)
        ttk.Button(queue_btn_frame, text="Remove Selected", command=self.remove_selected).pack(fill=tk.X, pady=2)
        ttk.Button(queue_btn_frame, text="Clear Queue", command=self.clear_queue).pack(fill=tk.X, pady=2)

        # --- 2. Output Destination ---
        output_frame = ttk.LabelFrame(main_frame, text="2. Output Destination", padding="10")
        output_frame.pack(fill=tk.X, pady=5)
        self.output_dir_entry = ttk.Entry(output_frame, textvariable=self.output_dir, state=tk.DISABLED)
        self.output_dir_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        self.browse_btn = ttk.Button(output_frame, text="Browse...", command=self.select_output_dir)
        self.browse_btn.pack(side=tk.LEFT)

        # --- 3. Encoding Options ---
        options_frame = ttk.LabelFrame(main_frame, text="3. Encoding Options", padding="10")
        options_frame.pack(fill=tk.X, pady=5)
        options_frame.columnconfigure(1, weight=1)
        options_frame.columnconfigure(3, weight=1)

        ttk.Label(options_frame, text="Video Codec:").grid(row=0, column=0, sticky="w")
        self.codec_combo = ttk.Combobox(options_frame, textvariable=self.video_codec, state="readonly", values=["H.265 (libx265)", "H.264 (libx264)"])
        self.codec_combo.grid(row=0, column=1, sticky="ew", padx=5)

        ttk.Label(options_frame, text="HW Accel:").grid(row=0, column=2, sticky="w", padx=10)
        self.hw_accel_combo = ttk.Combobox(options_frame, textvariable=self.hw_accel, state="readonly")
        self.hw_accel_combo.grid(row=0, column=3, sticky="ew", padx=5)
        self.hw_accel_combo.bind("<<ComboboxSelected>>", self.on_hw_accel_change)

        ttk.Label(options_frame, text="Quality Mode:").grid(row=1, column=0, sticky="w")
        self.mode_combo = ttk.Combobox(options_frame, textvariable=self.quality_mode, state="readonly", values=["CRF", "CBR"])
        self.mode_combo.grid(row=1, column=1, sticky="ew", padx=5)
        self.mode_combo.bind("<<ComboboxSelected>>", self.on_quality_mode_change)

        self.quality_label = ttk.Label(options_frame, text="CRF Value (18-28):")
        self.quality_label.grid(row=1, column=2, sticky="w", padx=10)
        self.quality_entry = ttk.Entry(options_frame, textvariable=self.quality_value, width=10)
        self.quality_entry.grid(row=1, column=3, sticky="w")

        ttk.Label(options_frame, text="Audio Codec:").grid(row=2, column=0, sticky="w")
        self.audio_combo = ttk.Combobox(options_frame, textvariable=self.audio_codec, state="readonly", values=["Copy", "AAC (192k)"])
        self.audio_combo.grid(row=2, column=1, sticky="ew", padx=5)
        self.on_quality_mode_change() # Set initial state

        # --- 4. Actions & Progress ---
        bottom_frame = ttk.Frame(main_frame)
        bottom_frame.pack(fill=tk.X, pady=5)
        self.shutdown_check = ttk.Checkbutton(bottom_frame, text="Shutdown when complete", variable=self.shutdown_var)
        self.shutdown_check.pack(side=tk.LEFT, pady=10)
        self.start_btn = ttk.Button(bottom_frame, text="Start Conversion", command=self.start_conversion)
        self.start_btn.pack(side=tk.RIGHT, ipady=10, padx=5)

        self.progress_bar = ttk.Progressbar(main_frame, orient="horizontal", length=100, mode="determinate")
        self.progress_bar.pack(fill=tk.X, pady=5)
        ttk.Label(main_frame, textvariable=self.status_label_var, wraplength=720).pack(fill=tk.X, pady=5)

    # --- UI Event Handlers ---
    def add_files(self):
        filepaths = filedialog.askopenfilenames(filetypes=(("Video Files", "*.mp4 *.mov *.avi *.mkv"), ("All files", "*.*")))
        for fp in filepaths:
            if fp not in self.files_to_convert:
                self.files_to_convert.append(fp)
                self.file_listbox.insert(tk.END, os.path.basename(fp))
        self.update_status_from_queue()

    def add_folder(self):
        folder = filedialog.askdirectory()
        if folder:
            for f in os.listdir(folder):
                if f.lower().endswith(('.mp4', '.mov', '.avi', '.mkv')):
                    fp = os.path.join(folder, f)
                    if fp not in self.files_to_convert:
                        self.files_to_convert.append(fp)
                        self.file_listbox.insert(tk.END, f)
        self.update_status_from_queue()

    def remove_selected(self):
        for i in sorted(self.file_listbox.curselection(), reverse=True):
            del self.files_to_convert[i]
            self.file_listbox.delete(i)
        self.update_status_from_queue()

    def clear_queue(self):
        self.files_to_convert.clear()
        self.file_listbox.delete(0, tk.END)
        self.update_status_from_queue()

    def select_output_dir(self):
        folder = filedialog.askdirectory()
        if folder: self.output_dir.set(folder)

    def on_quality_mode_change(self, event=None):
        mode = self.quality_mode.get()
        if mode == "CRF": self.quality_label.config(text="CRF Value (18-28):"); self.quality_value.set("23")
        elif mode == "CBR": self.quality_label.config(text="Bitrate (Mbps):"); self.quality_value.set("10")
        elif mode == "CQ": self.quality_label.config(text="CQ Value (0-51):"); self.quality_value.set("24")

    def on_hw_accel_change(self, event=None):
        hw = self.hw_accel.get()
        codecs, modes = (["H.265 (libx265)", "H.264 (libx264)"], ["CRF", "CBR"])
        if "None" not in hw:
            modes = ["CQ", "CBR"]
            available = self.available_encoders
            if "NVIDIA" in hw: codecs = [c for c in ["H.265 (hevc_nvenc)", "H.264 (h264_nvenc)"] if re.search(r'\((\S+)\)', c).group(1) in available]
            elif "Intel" in hw: codecs = [c for c in ["H.265 (hevc_qsv)", "H.264 (h264_qsv)"] if re.search(r'\((\S+)\)', c).group(1) in available]
            elif "Apple" in hw: codecs = [c for c in ["H.265 (hevc_videotoolbox)", "H.264 (h264_videotoolbox)"] if re.search(r'\((\S+)\)', c).group(1) in available]

        self.codec_combo['values'] = codecs if codecs else ["H.265 (libx265)"]
        self.video_codec.set(self.codec_combo['values'][0])
        self.mode_combo['values'] = modes
        self.quality_mode.set(modes[0])
        self.on_quality_mode_change()

    def toggle_ui_state(self, is_enabled):
        state = tk.NORMAL if is_enabled else tk.DISABLED
        for child in self.winfo_children():
            for widget in child.winfo_children():
                try:
                    # This is a bit brute-force, but effective for simple UIs
                    if isinstance(widget, (ttk.Button, ttk.Entry, ttk.Combobox, Listbox, ttk.Checkbutton)):
                         widget.configure(state=state)
                except tk.TclError: pass
        if is_enabled: self.on_quality_mode_change() # Re-apply disabled state on quality inputs

    # --- Core Logic & Threading ---
    def populate_hw_accel(self):
        self.status_label_var.set("Checking for available hardware encoders...")
        threading.Thread(target=self._populate_hw_accel_worker, daemon=True).start()

    def _populate_hw_accel_worker(self):
        try:
            self.available_encoders = self.converter.get_available_encoders()
            hw_options = ["None"]
            if any("nvenc" in e for e in self.available_encoders): hw_options.append("NVIDIA (nvenc)")
            if any("qsv" in e for e in self.available_encoders): hw_options.append("Intel (qsv)")
            if any("videotoolbox" in e for e in self.available_encoders): hw_options.append("Apple (videotoolbox)")
            self.progress_queue.put(("HW_ACCEL", hw_options))
        except (FFmpegError, FileNotFoundError) as e:
            self.progress_queue.put(("ERROR", f"ffmpeg not found. Please ensure it's in your system's PATH. Error: {e}"))

    def start_conversion(self):
        if not self.files_to_convert: messagebox.showerror("Error", "The file queue is empty."); return
        try: int(self.quality_value.get())
        except ValueError: messagebox.showerror("Error", "Quality/bitrate must be a number."); return

        self.is_converting = True
        self.toggle_ui_state(False)
        self.progress_bar['value'] = 0

        # Extract the ffmpeg codec name like 'libx265' from "H.265 (libx265)"
        codec_match = re.search(r'\((\S+)\)', self.video_codec.get())

        options = {
            'video_codec': codec_match.group(1) if codec_match else "libx265",
            'quality_mode': self.quality_mode.get().lower(),
            'quality_value': int(self.quality_value.get()),
            'audio_codec': 'aac' if 'AAC' in self.audio_codec.get() else 'copy',
            'hw_accel': self.hw_accel.get().split(" ")[-1].strip("()") if 'None' not in self.hw_accel.get() else None,
            'output_dir': self.output_dir.get(),
            'shutdown': self.shutdown_var.get()
        }
        threading.Thread(target=self.run_conversion_worker, args=(self.files_to_convert.copy(), options), daemon=True).start()

    def run_conversion_worker(self, files, options):
        for i, filepath in enumerate(files):
            try:
                base, _ = os.path.splitext(os.path.basename(filepath))
                output_path = os.path.join(options['output_dir'], f"{base}_converted.mp4")
                self.progress_queue.put(("STATUS", f"({i+1}/{len(files)}) Converting {base}..."))
                self.converter.convert(filepath, output_path, **options, progress_callback=self.progress_callback)
            except (FFmpegError, FileNotFoundError) as e:
                self.progress_queue.put(("ERROR", f"Failed on {os.path.basename(filepath)}: {e}")); return
            except Exception as e:
                self.progress_queue.put(("ERROR", f"An unexpected error occurred: {e}")); return

        if options['shutdown']:
            self.progress_queue.put(("SHUTDOWN", "All tasks complete! Shutting down in 60 seconds..."))
        else:
            self.progress_queue.put(("DONE", "All conversions finished!"))

    def progress_callback(self, percentage, message):
        self.progress_queue.put(("PROGRESS", percentage, message))

    def process_progress_queue(self):
        try:
            item = self.progress_queue.get_nowait()
            msg_type, *payload = item

            if msg_type == "PROGRESS":
                percentage, message = payload
                self.progress_bar['value'] = percentage
                self.status_label_var.set(message)
            elif msg_type == "STATUS":
                self.status_label_var.set(payload[0])
            elif msg_type == "DONE":
                self.is_converting, self.toggle_ui_state = False, self.toggle_ui_state(True)
                self.status_label_var.set(payload[0])
                messagebox.showinfo("Success", "All videos converted successfully.")
            elif msg_type == "ERROR":
                self.is_converting, self.toggle_ui_state = False, self.toggle_ui_state(True)
                self.status_label_var.set(f"An error occurred: {payload[0]}")
                messagebox.showerror("Error", payload[0])
            elif msg_type == "HW_ACCEL":
                self.hw_accel_combo['values'] = payload[0]
                self.status_label_var.set("Ready. Add files to the queue to begin.")
            elif msg_type == "SHUTDOWN":
                self.status_label_var.set(payload[0])
                self.initiate_shutdown()

        except queue.Empty:
            pass
        finally:
            self.after(100, self.process_progress_queue)

    def update_status_from_queue(self):
        if not self.is_converting:
            self.status_label_var.set(f"{len(self.files_to_convert)} file(s) in queue.")

    def initiate_shutdown(self):
        system = platform.system()
        try:
            if system == "Windows": os.system("shutdown /s /t 60")
            elif system == "Darwin" or system == "Linux": os.system("sudo shutdown -h +1")
            else: self.progress_queue.put(("ERROR", "Shutdown is not supported on this OS."))
        except Exception as e:
            self.progress_queue.put(("ERROR", f"Failed to initiate shutdown: {e}"))

if __name__ == "__main__":
    app = App()
    app.mainloop()

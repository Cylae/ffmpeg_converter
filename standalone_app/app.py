import tkinter as tk
from tkinter import ttk, filedialog, messagebox, Listbox
import os
import sys
import threading
import queue
import platform

# Add the parent directory to the path to find the core module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from core.ffmpeg_core import FFmpegConverter, FFmpegError

class App(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Advanced Video Converter")
        self.geometry("750x650")
        self.resizable(False, False)

        self.converter = FFmpegConverter()
        self.files_to_convert = []
        self.progress_queue = queue.Queue()
        self.is_converting = False

        # --- UI Styling ---
        style = ttk.Style(self)
        style.theme_use('clam')
        style.configure("TButton", padding=6, relief="flat")
        style.configure("TLabel", padding=5)
        style.configure("TEntry", padding=5)

        # --- Main Frame ---
        main_frame = ttk.Frame(self, padding="15")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # --- File Queue ---
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

        # --- Output Directory ---
        output_frame = ttk.LabelFrame(main_frame, text="2. Output Destination", padding="10")
        output_frame.pack(fill=tk.X, pady=5)
        self.output_dir = tk.StringVar(value=os.path.expanduser("~"))
        ttk.Entry(output_frame, textvariable=self.output_dir, state=tk.DISABLED).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        self.browse_btn = ttk.Button(output_frame, text="Browse...", command=self.select_output_dir)
        self.browse_btn.pack(side=tk.LEFT)

        # --- Encoding Options ---
        options_frame = ttk.LabelFrame(main_frame, text="3. Encoding Options", padding="10")
        options_frame.pack(fill=tk.X, pady=5)

        # Codec, HW Accel, Mode, Quality
        ttk.Label(options_frame, text="Video Codec:").grid(row=0, column=0, sticky="w")
        self.video_codec = tk.StringVar(value="H.265 (libx265)")
        self.codec_combo = ttk.Combobox(options_frame, textvariable=self.video_codec, state="readonly", values=["H.265 (libx265)", "H.264 (libx264)", "AV1 (libsvtav1)"])
        self.codec_combo.grid(row=0, column=1, sticky="ew", padx=5)

        ttk.Label(options_frame, text="HW Accel:").grid(row=0, column=2, sticky="w", padx=10)
        self.hw_accel = tk.StringVar(value="None")
        self.hw_accel_combo = ttk.Combobox(options_frame, textvariable=self.hw_accel, state="readonly")
        self.hw_accel_combo.grid(row=0, column=3, sticky="ew", padx=5)

        ttk.Label(options_frame, text="Quality Mode:").grid(row=1, column=0, sticky="w")
        self.quality_mode = tk.StringVar(value="crf")
        self.mode_combo = ttk.Combobox(options_frame, textvariable=self.quality_mode, state="readonly", values=["CRF", "CBR"])
        self.mode_combo.grid(row=1, column=1, sticky="ew", padx=5)
        self.mode_combo.bind("<<ComboboxSelected>>", self.update_ui_for_mode)

        self.quality_label = ttk.Label(options_frame, text="CRF Value (18-28):")
        self.quality_label.grid(row=1, column=2, sticky="w", padx=10)
        self.quality_value = tk.StringVar(value="23")
        self.quality_entry = ttk.Entry(options_frame, textvariable=self.quality_value, width=10)
        self.quality_entry.grid(row=1, column=3, sticky="w")

        # Audio
        ttk.Label(options_frame, text="Audio Codec:").grid(row=2, column=0, sticky="w")
        self.audio_codec = tk.StringVar(value="Copy")
        self.audio_combo = ttk.Combobox(options_frame, textvariable=self.audio_codec, state="readonly", values=["Copy", "AAC (192k)"])
        self.audio_combo.grid(row=2, column=1, sticky="ew", padx=5)
        options_frame.columnconfigure(1, weight=1)
        options_frame.columnconfigure(3, weight=1)

        # --- Start & Progress ---
        bottom_frame = ttk.Frame(main_frame)
        bottom_frame.pack(fill=tk.BOTH, expand=True, pady=5)

        self.shutdown_var = tk.BooleanVar()
        self.shutdown_check = ttk.Checkbutton(bottom_frame, text="Shutdown when complete", variable=self.shutdown_var)
        self.shutdown_check.pack(side=tk.LEFT, pady=10)

        self.start_btn = ttk.Button(bottom_frame, text="Start Conversion", command=self.start_export)
        self.start_btn.pack(side=tk.RIGHT, ipady=10, padx=5)

        self.progress_bar = ttk.Progressbar(main_frame, orient="horizontal", length=100, mode="determinate")
        self.progress_bar.pack(fill=tk.X, pady=5)
        self.status_label_var = tk.StringVar(value="Add files to the queue to begin.")
        ttk.Label(main_frame, textvariable=self.status_label_var, wraplength=720).pack(fill=tk.X, pady=5)

        self.after(100, self.populate_hw_accel)
        self.process_queue()

    def populate_hw_accel(self):
        self.status_label_var.set("Checking for available hardware encoders...")
        threading.Thread(target=self._populate_hw_accel_worker, daemon=True).start()

    def _populate_hw_accel_worker(self):
        try:
            encoders = self.converter.get_available_encoders()
            hw_options = ["None"]
            if any("nvenc" in e for e in encoders):
                hw_options.append("NVIDIA (nvenc)")
            if any("qsv" in e for e in encoders):
                hw_options.append("Intel (qsv)")
            if any("videotoolbox" in e for e in encoders):
                hw_options.append("Apple (videotoolbox)")
            self.progress_queue.put(("HW_ACCEL", hw_options))
        except (FFmpegError, FileNotFoundError) as e:
            self.progress_queue.put(("ERROR", f"Could not find ffmpeg. Please ensure it's installed and in your PATH. Details: {e}"))


    def add_files(self):
        filepaths = filedialog.askopenfilenames(
            title="Select Video File(s)",
            filetypes=(("Video Files", "*.mp4 *.mov *.avi *.mkv *.wmv"), ("All files", "*.*"))
        )
        for fp in filepaths:
            if fp not in self.files_to_convert:
                self.files_to_convert.append(fp)
                self.file_listbox.insert(tk.END, os.path.basename(fp))
        self.update_status_from_queue()

    def add_folder(self):
        folderpath = filedialog.askdirectory(title="Select a Folder")
        if folderpath:
            for f in os.listdir(folderpath):
                if f.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.wmv')):
                    fp = os.path.join(folderpath, f)
                    if fp not in self.files_to_convert:
                        self.files_to_convert.append(fp)
                        self.file_listbox.insert(tk.END, f)
        self.update_status_from_queue()

    def remove_selected(self):
        selected_indices = self.file_listbox.curselection()
        for i in sorted(selected_indices, reverse=True):
            del self.files_to_convert[i]
            self.file_listbox.delete(i)
        self.update_status_from_queue()

    def clear_queue(self):
        self.files_to_convert.clear()
        self.file_listbox.delete(0, tk.END)
        self.update_status_from_queue()

    def update_status_from_queue(self):
        if not self.is_converting:
            count = len(self.files_to_convert)
            self.status_label_var.set(f"{count} file(s) in queue.")

    def select_output_dir(self):
        folderpath = filedialog.askdirectory(title="Select Output Directory")
        if folderpath:
            self.output_dir.set(folderpath)

    def update_ui_for_mode(self, event=None):
        if self.quality_mode.get() == "CRF":
            self.quality_label.config(text="CRF Value (18-28):")
            self.quality_value.set("23")
        else: # CBR
            self.quality_label.config(text="Bitrate (Mbps):")
            self.quality_value.set("10")

    def start_export(self):
        if not self.files_to_convert:
            messagebox.showerror("Error", "The file queue is empty.")
            return

        try:
            quality_val = int(self.quality_value.get())
        except ValueError:
            messagebox.showerror("Error", "Invalid quality/bitrate value. Please enter a number.")
            return

        self.is_converting = True
        self.toggle_ui_state(tk.DISABLED)
        self.progress_bar['value'] = 0

        conversion_options = {
            'video_codec': self.video_codec.get().split(" ")[-1].strip("()"),
            'quality_mode': self.quality_mode.get().lower(),
            'quality_value': quality_val,
            'audio_codec': 'aac' if 'AAC' in self.audio_codec.get() else 'copy',
            'hw_accel': self.hw_accel.get().split(" ")[-1].strip("()") if 'None' not in self.hw_accel.get() else None,
            'output_dir': self.output_dir.get(),
            'shutdown': self.shutdown_var.get()
        }

        threading.Thread(target=self.run_conversion_worker, args=(self.files_to_convert.copy(), conversion_options), daemon=True).start()

    def run_conversion_worker(self, files, options):
        total_files = len(files)
        for i, filepath in enumerate(files):
            try:
                base, _ = os.path.splitext(os.path.basename(filepath))
                output_path = os.path.join(options['output_dir'], f"{base}_converted.mp4")

                self.progress_queue.put((-1, f"({i+1}/{total_files}) Converting {base}..."))

                self.converter.convert(
                    filepath, output_path,
                    video_codec=options['video_codec'],
                    quality_mode=options['quality_mode'],
                    quality_value=options['quality_value'],
                    audio_codec=options['audio_codec'],
                    hw_accel=options['hw_accel'],
                    progress_callback=self.progress_callback
                )
            except (FFmpegError, FileNotFoundError) as e:
                self.progress_queue.put(("ERROR", f"ERROR on {os.path.basename(filepath)}: {e}"))
                break # Stop on first error
            except Exception as e:
                self.progress_queue.put(("ERROR", f"An unexpected error occurred: {e}"))
                break # Stop on first error

        if options['shutdown']:
            self.progress_queue.put((-1, "All tasks complete! Shutting down in 60 seconds..."))
            self.initiate_shutdown()
        else:
            self.progress_queue.put(("DONE", "All tasks complete!"))

    def initiate_shutdown(self):
        system = platform.system()
        try:
            if system == "Windows":
                os.system("shutdown /s /t 60")
            elif system == "Darwin" or system == "Linux":
                # Note: This requires the user to have passwordless sudo for shutdown.
                # A safer approach would be to just notify the user.
                os.system("sudo shutdown -h +1")
            else:
                self.progress_queue.put(("ERROR", "Shutdown is not supported on this OS."))
        except Exception as e:
            self.progress_queue.put(("ERROR", f"Failed to initiate shutdown: {e}"))


    def progress_callback(self, percentage, message):
        self.progress_queue.put((percentage, message))

    def process_queue(self):
        try:
            content = self.progress_queue.get_nowait()
            if isinstance(content, tuple) and len(content) == 2:
                tag, value = content
                if tag == "DONE":
                    self.is_converting = False
                    self.toggle_ui_state(tk.NORMAL)
                    self.status_label_var.set("All conversions finished!")
                    messagebox.showinfo("Success", "All video conversions have been completed.")
                elif tag == "ERROR":
                    self.is_converting = False
                    self.toggle_ui_state(tk.NORMAL)
                    self.status_label_var.set(f"An error occurred: {value}")
                    messagebox.showerror("Error", value)
                elif tag == "HW_ACCEL":
                    self.hw_accel_combo['values'] = value
                    self.status_label_var.set("Ready. Add files to the queue to begin.")
                else: # Progress update
                    percentage, message = tag, value
                    if percentage > -1:
                        self.progress_bar['value'] = percentage
                    self.status_label_var.set(message)
        except queue.Empty:
            pass
        finally:
            self.after(100, self.process_queue)

    def toggle_ui_state(self, state):
        for child in self.winfo_children():
            # This is a bit aggressive but effective for disabling everything
            for widget in child.winfo_children():
                try:
                    if isinstance(widget, ttk.Frame):
                         for w in widget.winfo_children(): w.configure(state=state)
                    else:
                        widget.configure(state=state)
                except tk.TclError:
                    pass # Some widgets like Labels don't have a 'state'
        # Manually enable/disable what's necessary
        self.start_btn.config(state=state)
        if state == tk.NORMAL:
            self.update_ui_for_mode()
            self.status_label_var.set(f"{len(self.files_to_convert)} file(s) in queue.")

if __name__ == "__main__":
    app = App()
    app.mainloop()

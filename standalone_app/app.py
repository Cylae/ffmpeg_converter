import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os
import sys
import threading
import queue

# Add the parent directory to the path to find the core module
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from core.ffmpeg_core import FFmpegConverter, FFmpegError

class App(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("H.265 Video Converter")
        self.geometry("600x450")
        self.resizable(False, False)

        self.converter = FFmpegConverter()
        self.files_to_convert = []
        self.progress_queue = queue.Queue()

        # UI Styling
        style = ttk.Style(self)
        style.theme_use('clam')

        # --- Main Frame ---
        main_frame = ttk.Frame(self, padding="15")
        main_frame.pack(fill=tk.BOTH, expand=True)

        # --- File Selection ---
        selection_frame = ttk.LabelFrame(main_frame, text="1. Select Files", padding="10")
        selection_frame.pack(fill=tk.X, pady=5)

        self.select_file_btn = ttk.Button(selection_frame, text="Select Video File", command=self.select_file)
        self.select_file_btn.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)

        self.select_folder_btn = ttk.Button(selection_frame, text="Select Folder (Batch)", command=self.select_folder)
        self.select_folder_btn.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=5)

        # --- Encoding Options ---
        options_frame = ttk.LabelFrame(main_frame, text="2. Choose Encoding Options", padding="10")
        options_frame.pack(fill=tk.X, pady=5)

        self.mode = tk.StringVar(value="crf")

        crf_radio = ttk.Radiobutton(options_frame, text="Constant Quality (CRF)", variable=self.mode, value="crf", command=self.update_ui_for_mode)
        crf_radio.grid(row=0, column=0, sticky="w", padx=5)

        self.crf_label = ttk.Label(options_frame, text="CRF Value (18-28):")
        self.crf_label.grid(row=0, column=1, sticky="w", padx=5)
        self.crf_value = tk.StringVar(value="23")
        self.crf_entry = ttk.Entry(options_frame, textvariable=self.crf_value, width=10)
        self.crf_entry.grid(row=0, column=2, sticky="w")

        cbr_radio = ttk.Radiobutton(options_frame, text="Constant Bitrate (CBR)", variable=self.mode, value="cbr", command=self.update_ui_for_mode)
        cbr_radio.grid(row=1, column=0, sticky="w", padx=5)

        self.cbr_label = ttk.Label(options_frame, text="Bitrate (Mbps):")
        self.cbr_label.grid(row=1, column=1, sticky="w", padx=5)
        self.cbr_value = tk.StringVar(value="10")
        self.cbr_entry = ttk.Entry(options_frame, textvariable=self.cbr_value, width=10)
        self.cbr_entry.grid(row=1, column=2, sticky="w")

        # --- Start Export ---
        export_frame = ttk.LabelFrame(main_frame, text="3. Start Export", padding="10")
        export_frame.pack(fill=tk.X, pady=5)

        self.start_btn = ttk.Button(export_frame, text="Start Export", command=self.start_export)
        self.start_btn.pack(fill=tk.X, ipady=10)

        # --- Progress & Status ---
        progress_frame = ttk.LabelFrame(main_frame, text="Progress", padding="10")
        progress_frame.pack(fill=tk.X, pady=5)

        self.progress_bar = ttk.Progressbar(progress_frame, orient="horizontal", length=100, mode="determinate")
        self.progress_bar.pack(fill=tk.X, pady=5)

        self.status_label_var = tk.StringVar(value="Select a file or folder to begin.")
        self.status_label = ttk.Label(progress_frame, textvariable=self.status_label_var, wraplength=550)
        self.status_label.pack(fill=tk.X, pady=5)

        self.update_ui_for_mode()
        self.process_queue()

    def update_ui_for_mode(self):
        is_crf = self.mode.get() == "crf"
        self.crf_entry.config(state=tk.NORMAL if is_crf else tk.DISABLED)
        self.crf_label.config(state=tk.NORMAL if is_crf else tk.DISABLED)
        self.cbr_entry.config(state=tk.NORMAL if not is_crf else tk.DISABLED)
        self.cbr_label.config(state=tk.NORMAL if not is_crf else tk.DISABLED)

    def select_file(self):
        filepath = filedialog.askopenfilename(
            title="Select a Video File",
            filetypes=(("Video Files", "*.mp4 *.mov *.avi *.mkv *.wmv"), ("All files", "*.*"))
        )
        if filepath:
            self.files_to_convert = [filepath]
            self.status_label_var.set(f"Selected file: {os.path.basename(filepath)}")

    def select_folder(self):
        folderpath = filedialog.askdirectory(title="Select a Folder for Batch Conversion")
        if folderpath:
            self.files_to_convert = [
                os.path.join(folderpath, f) for f in os.listdir(folderpath)
                if f.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.wmv'))
            ]
            if self.files_to_convert:
                self.status_label_var.set(f"Selected {len(self.files_to_convert)} files for batch conversion.")
            else:
                self.status_label_var.set("No video files found in the selected folder.")

    def start_export(self):
        if not self.files_to_convert:
            messagebox.showerror("Error", "No files selected for conversion.")
            return

        options = {}
        try:
            if self.mode.get() == 'crf':
                options['mode'] = 'crf'
                options['value'] = int(self.crf_value.get())
            else:
                options['mode'] = 'cbr'
                options['value'] = int(self.cbr_value.get())
        except ValueError:
            messagebox.showerror("Error", "Invalid input for CRF or Bitrate. Please enter a number.")
            return

        self.toggle_ui_state(tk.DISABLED)
        self.progress_bar['value'] = 0

        # Run conversion in a separate thread to avoid freezing the GUI
        self.conversion_thread = threading.Thread(
            target=self.run_conversion_worker,
            args=(self.files_to_convert.copy(), options),
            daemon=True
        )
        self.conversion_thread.start()

    def run_conversion_worker(self, files, options):
        total_files = len(files)
        for i, filepath in enumerate(files):
            try:
                base, _ = os.path.splitext(filepath)
                output_path = f"{base}_h265.mp4"

                self.progress_queue.put((-1, f"({i+1}/{total_files}) Starting conversion for {os.path.basename(filepath)}..."))

                self.converter.convert(filepath, output_path, options, self.progress_callback)

            except (FFmpegError, FileNotFoundError) as e:
                self.progress_queue.put((-1, f"ERROR: {e}"))
            except Exception as e:
                self.progress_queue.put((-1, f"An unexpected error occurred: {e}"))

        self.progress_queue.put(("DONE", "All tasks complete!"))


    def progress_callback(self, percentage, message):
        self.progress_queue.put((percentage, message))

    def process_queue(self):
        try:
            percentage, message = self.progress_queue.get_nowait()

            if percentage != -1:
                self.progress_bar['value'] = percentage

            if message == "DONE":
                self.toggle_ui_state(tk.NORMAL)
                self.status_label_var.set("All conversions finished!")
                messagebox.showinfo("Success", "All video conversions have been completed successfully.")
            else:
                self.status_label_var.set(message)

        except queue.Empty:
            pass
        finally:
            self.after(100, self.process_queue)

    def toggle_ui_state(self, state):
        self.select_file_btn.config(state=state)
        self.select_folder_btn.config(state=state)
        self.start_btn.config(state=state)
        for child in self.children['!frame'].children['!labelframe2'].winfo_children():
            if isinstance(child, (ttk.Radiobutton, ttk.Entry, ttk.Label)):
                child.config(state=state)
        # Always call update_ui_for_mode to ensure disabled states are correct
        if state == tk.NORMAL:
            self.update_ui_for_mode()


if __name__ == "__main__":
    app = App()
    app.mainloop()

import subprocess
import sys
import os

def main():
    """Runs the PyInstaller command to build the executable."""

    # The main script of the application
    script_to_package = os.path.join('standalone_app', 'app.py')

    # The name of the final executable
    executable_name = 'Advanced Video Converter'

    # PyInstaller command
    # --onefile: Package into a single executable
    # --windowed: Do not show a console window when the app runs
    # --name: The name for the executable and build artifacts
    command = [
        sys.executable,  # Use the same python that runs the build script
        '-m', 'PyInstaller',
        '--onefile',
        '--windowed',
        '--name', executable_name,
        script_to_package
    ]

    print(f"Running command: {' '.join(command)}")

    try:
        # Using subprocess.run to execute the command
        # Run the command and stream output directly to the console
        process = subprocess.run(
            command,
            check=True,
            encoding='utf-8'
        )
        print("\nBuild successful!")
        print(f"Executable created in the '{os.path.join(os.getcwd(), 'dist')}' folder.")
        # Optionally print the stdout from PyInstaller on success for more info
        # print(process.stdout)

    except subprocess.CalledProcessError as e:
        print("\n--- Build Failed! ---")
        print("PyInstaller encountered an error. See the output below for details.")
        print("\n--- STDOUT ---")
        print(e.stdout)
        print("\n--- STDERR ---")
        print(e.stderr)
        print("-------------------")
        sys.exit(1)
    except FileNotFoundError:
        print("\nError: PyInstaller not found.")
        print("Please install it with: pip install pyinstaller")
        sys.exit(1)

if __name__ == '__main__':
    main()

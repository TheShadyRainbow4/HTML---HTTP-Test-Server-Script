<a id="readme-top"></a>

<!-- EliteSoftware Co. LOGO -->

<br />
<div align="center">
<a href="Logo">
<img src="https://i.postimg.cc/85MDTcrJ/Elite-Software-LOGO-Mocup2.png" alt="Logo" width="256" height="256">
</a>
</div>

<!-- ABOUT THE PROJECT -->

# 💾 About The Project <div align="center">
## Screenshot may be slightly outdated. Sorry in advance! :)  
<br />
<div align="center">
<a href="Screenshot">
<img src="https://i.postimg.cc/Y9QyWx7m/image.png" alt="GUI Screenshot" width="1280" height="720">
</a>
</div>

EliteSoftware HTML - HTTP Test Server: A Multi-Config GUI for PowerShell

EliteSoftware HTML - HTTP Test Server is a compact, multi-threaded HTTP server application built entirely with PowerShell and Windows Forms (.NET WinForms). It's designed to provide developers and testers with a simple, yet robust, GUI-based platform for quickly hosting and testing local static web content (HTML, CSS, JS, etc.).

This tool allows you to run multiple server configurations simultaneously, each on its own thread, ensuring stability and non-blocking operation. It features a modern, themed GUI, configuration saving, dynamic port checking, and a graceful shutdown mechanism.

Built by: Zachary Whiteman & Google Gemini AI.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->

# 🔰 Getting Started
This application is a single PowerShell script and does not require a complex installation process.

## 🕰️ Prerequisites
To run this script, you only need:

Windows Operating System (Windows 7 or later).

PowerShell 5.1 or newer (PowerShell Core is supported, but the script is optimized for the full .NET Framework available in Windows PowerShell for WinForms).

The required .NET Framework assemblies (System.Windows.Forms, System.Drawing, System.Net) which are included with modern Windows installations and loaded automatically by the script.

## 💽 Installation & Execution
Download: Download the EliteSoftware HTML - HTTP Test Server.PS1 script file.

Unblock: Right-click the file, go to Properties, and click Unblock if the file was downloaded from the internet (a common necessity for scripts downloaded from the web).

Run: Execute the script from a PowerShell console or by double-clicking it (if your system is configured to run PS1 files).

.\EliteSoftware HTML - HTTP Test Server.PS1

The application's configuration files and custom icon (if present) are stored in:
C:\Users\<YourUser>\AppData\Roaming\EliteSoftware\HTML_HTTP_TEST_SERVER

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 🚀 Usage
The application is designed for rapid local testing via a simple three-step process:

Configure: In the main control panel, specify the Server Root Folder (where your HTML/CSS/JS files are located) and the desired Server Port (e.g., 8080).

Start: Click the "Start Server" button. The application will automatically check for port availability and launch the server on a dedicated thread.

Test: Click the "Open in Browser" button to immediately launch the hosted URL in your default web browser, allowing you to test your content instantly.

Use the left sidebar to save and switch between up to 10 distinct server configurations instantly.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## ✨ Key Features
This application leverages PowerShell WinForms and multi-threading for a fully-featured desktop experience:

Multi-Server Configuration UI: Manage up to 10 distinct server setups with their own root paths, default files, and ports via an intuitive sidebar and configuration list.

Multi-Threaded HTTP Server: The server logic uses the robust System.Net.HttpListener on a separate background thread, ensuring the GUI remains responsive while handling incoming requests.

Dynamic Port Resolution: Automatically detects and increments the server port by +1 if the specified port is already in use, preventing startup conflicts.

Detailed Real-Time Logging: Logs all successful (200), 404 Not Found, and 500 Server Error requests to the GUI console in real-time. Logs include file size (in KB), client IP, and HTTP method.

Graceful Shutdown: Implements an explicit shutdown routine for all active servers and includes a custom, themed "Goodbye" popup window on exit, ensuring no lingering processes.

Configuration Persistence: Automatically saves and loads all server settings (up to 10 configs) to a JSON file in your AppData folder, maintaining your workflow across sessions.

Browser Integration: Includes a one-click button to open the hosted server URL in the default web browser.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 🛠️ Technology Stack
The entire application is a self-contained PowerShell script, utilizing:

Scripting Language: PowerShell (5.1+)

GUI Framework: .NET Windows Forms (WinForms)

Core HTTP Service: System.Net.HttpListener (a high-performance, built-in Windows HTTP service)

Threading: System.Threading.Thread for non-blocking server operation.

GUI Styling: Uses [System.Windows.Forms.Application]::EnableVisualStyles() and System.Drawing.Drawing2D for custom, system-themed buttons and gradient headers.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 📐 Architecture & Security Notes

This application is built as a highly specialized, local-only test environment. Understanding its architecture is key to proper usage and security:

### 🌎 Local-Only Server (HttpListener)
The core server functionality is provided by the `.NET System.Net.HttpListener` class. This class is highly optimized for lightweight serving and is configured to:
* **Prevent Global Access:** The default IP address binding is set to `127.0.0.1` (localhost) to ensure the server is not accidentally accessible from external network connections. This is crucial for security when testing local files.
* **Static Content Only:** The server is designed exclusively to serve static files (HTML, CSS, JavaScript, images, etc.). It does **not** execute any server-side scripts (like PHP or ASP.NET) and is safe to use for testing front-end components.

### 🔄️ Threading Model
The GUI runs on the main PowerShell thread, while the `HttpListener` operates on a separate, dedicated `System.Threading.Thread`. This architecture ensures:
* **Non-Blocking UI:** The user interface remains responsive to clicks and input, even while the server is busy handling requests.
* **Graceful Exit:** The script uses a global flag (`$Script:IsExiting`) and explicit `Stop()` calls on the listener to guarantee that the server threads are terminated cleanly when the application window is closed.

### 🗃️ Data Handling
Configuration data for up to 10 servers (root path, port, default file) is stored locally as a simple JSON file in the designated AppData directory. No external connections or databases are used for configuration or logging.

<!-- LICENSE -->

## 🪪 License
Distributed under the MIT License. See LICENSE.txt for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->

## ☎️ Contact
Zach Whiteman - elitesoftwarecolimited@gmail.com

HuggingFace - https://huggingface.co/EliteSoftware

HuggingFace (Personal) - https://huggingface.co/TheShadyRainbow

LinkTree - https://linktr.ee/zachrainbow

Patreon - https://www.patreon.com/c/EliteSoftwareCo

<p align="right">(<a href="#readme-top">back to top</a>)</p>


## Scope
Outlines the core functions, limitations, and operational boundaries of the HTML---HTTP-Test-Server-Script utility.

## Plans
Roadmap includes UI refinements, bug fixes, and expanded compatibility options.

## Development
Built in accordance with EliteSoftware GUI development guidelines.
- **Framework**: .NET Framework 4.6 / WinForms
- **Visual Styles**: Enabled
- **Apartment State**: STA Mode enforced for GUI reliability.

## What It Is
A dedicated system utility developed by EliteSoftwareTech Co. to perform system tasks cleanly and efficiently.

## How to Use
1. Launch the utility.
2. Follow the on-screen instructions or refer to tooltips for interactive elements.
3. Access Settings from the main menu for configuration.

---
### EliteSoftwareTech Co. - GUI Guidelines
- **Authors**: Zachary Whiteman, Susan Gemm, TheShadyRainbow4, EliteSoftwareTech Co.
- **Company**: EliteSoftware / EliteSoftwareTech Co.
- **Document Version**: 1.2.0.0
- **Target Framework**: .NET Framework 4.6 (WinForms / Legacy Win32)
- **Minimum OS Target**: Windows Vista / Windows 7
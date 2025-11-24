# Super Resolution

A high-performance Flutter application for upscaling images using the **Real-ESRGAN** model.

This project is distinguished by its specific optimization for macOS: it utilizes a **custom-compiled TensorFlow Lite dylib with Metal support**, enabling GPU-accelerated inference that is drastically faster than standard CPU implementations.

![Model](https://img.shields.io/badge/Model-Real--ESRGAN-ff69b4?style=for-the-badge) ![Performance](https://img.shields.io/badge/Performance-Metal_Accelerated-orange?style=for-the-badge) ![Resolutions](https://img.shields.io/badge/Scale-4K_|_8K-blueviolet?style=for-the-badge)

## 🚀 Unbelievable Speed on macOS

Standard TFLite implementations rely on the CPU, which makes upscaling to high resolutions excruciatingly slow.

**This project solves that bottleneck.**

By linking against a custom-built `libtensorflowlite_c.dylib` with the **Metal Delegate** enabled, this app offloads the heavy matrix calculations directly to the Mac's GPU.


* **Result:** Inference is not just smoother; it is **unbelievably faster**.
* **Capability:** This massive performance headroom allows for practical upscaling to **1080p, 1440p, 4K, and even 8K** in reasonable timeframes.

## 🛠️ Technical Implementation

* **Model Architecture**: Real-ESRGAN (Superior texture and detail reconstruction).
* **Inference Engine**: TensorFlow Lite (Custom Build).
* **Hardware Acceleration**: Apple Metal API (via TFLite Delegate).
* **Frontend**: Flutter.

# SoilScope

**An iPhone research app for soil-moisture estimates and watering guidance.**

Created by **Paul Schnabl**, a high-school freshman, for the **2026 Congressional App Challenge**.

## What the app does

1. Capture a photo of a plant and nearby soil.
2. Outline the area using four movable corners.
3. Set physical scale with supported iPhone LiDAR or a known-length reference.
4. Estimate soil moisture using a local machine-learning model.
5. Enter crop, soil, area, and watering efficiency, then request local weather to preview a suggested water amount.

Photo analysis runs on the iPhone without an internet connection. Photos are not uploaded for inference. The optional weather request uses Open-Meteo and the device's location.

## My contribution

I collected research data, developed and compared soil-moisture models in Python, and developed the irrigation calculations. I designed the interface, wrote pseudocode, and tested and troubleshot the app. Codex assisted with translating my models and pseudocode into Swift and connecting them to my interface design.

## Guide for judges

| File | Purpose |
| --- | --- |
| [LocalVineyardModel.swift](SoilScope/LocalVineyardModel.swift) | Image features and frozen moisture-model coefficients |
| [ScanModel.swift](SoilScope/ScanModel.swift) | Capture, scale, selection, and inference |
| [WaterPlan.swift](SoilScope/WaterPlan.swift) | Weather requests and irrigation calculations |
| [ContentView.swift](SoilScope/ContentView.swift) | SwiftUI interface |
| [SoilScopeApp.swift](SoilScope/SoilScopeApp.swift) | App entry point |

This repository contains the Swift iPhone implementation. The earlier Python training scripts, raw research data, and evaluation results are not included in this package.

## Run in Xcode

1. Download or clone this repository on a Mac with Xcode and support for iOS 17 or later.
2. Open `SoilScope.xcodeproj`.
3. Select your own signing team under Signing & Capabilities. Change the bundle identifier if needed.
4. Select an ARKit-capable iPhone running iOS 17 or later and run the app.
5. Allow camera access. Location access and internet are needed only for local weather.

A LiDAR-capable device can provide automatic scale; other supported devices use a manual reference. Use a physical iPhone to demonstrate capture. Simulator camera and LiDAR behavior have not been verified.

## Research status

This is an experimental prototype, not a validated moisture meter or irrigation controller. The included frozen model was trained on six vineyard observations. The Swift image-feature implementation has not yet been numerically matched against the original Python extractor, and earlier research results do not establish phone-app accuracy. Users should verify estimates with a soil probe before watering.

The displayed watering range is a what-if scenario, not a statistical confidence interval. The crop and soil settings affect the irrigation calculations; they do not select separately trained moisture models.

See [research and implementation notes](docs/RESEARCH_NOTES.md) for the model background, scale assumptions, and limitations.

## Tools and languages

- **Swift / SwiftUI:** iPhone app and interface
- **ARKit / Core Image:** camera, depth, and image processing
- **Xcode:** app development and device testing
- **Python:** earlier model research (not included here)
- **Codex:** coding assistance
- **Open-Meteo:** optional local weather forecast

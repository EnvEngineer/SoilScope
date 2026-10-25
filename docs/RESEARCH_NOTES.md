# SoilScope

Independent native iPhone research app using the existing Iron Horse Vineyard Field F moisture model. One photo and one four-point selection produce **one** VWC estimate; the image is not split into tiles. Moisture inference runs on the iPhone without a server or ML API. The optional weather forecast still uses an internet API.

## What you select

Capture a view with an ARKit-capable iPhone. The camera has one **Capture image** button fixed on screen. On a LiDAR model, the camera shows live depth state: green means depth and tracking are ready, with estimated ground distance and camera tilt; orange means scale will be entered manually after capture. The captured frame determines the path automatically: valid LiDAR depth supplies scale, otherwise the next screen asks you to put a ruler or other known length flat on the same ground plane, drag A and B to its endpoints, and enter its length in centimetres. To favor soil behind leaves, the depth estimate uses the farther 85th percentile of valid readings in the central view, not the nearest leaf or a potentially noisy single maximum. Drag the four numbered points to outline the relevant ground at **any physical size**. The selection display includes its longest side. Frame vines and the soil beside/beneath them as in the model's training crops; aisle-only imagery is outside its validated geometry. Moving a point, moving the reference, or editing its length clears the previous estimate.

LiDAR or a manual reference supplies an approximate physical scale; neither measures moisture. A manual reference must be on the same ground plane as the selected soil or its scale can be wrong. The app adjusts the plant-adjacent distance band, vegetation-mask morphology, and texture offsets using that scale. The original training crops were roughly 2 × 2 m and near-downward, but image size and view angle no longer block a water suggestion. Estimates from other sizes or oblique views remain unvalidated extrapolations. The points control which pixels reach the model; they do not retrain the model or make aisle soil equivalent to under-vine soil.

## The model

`SoilScope/LocalVineyardModel.swift` contains the frozen Field F model coefficients from the archived `Desktop/IHV Research/ihv_field_f_holdout/test_expanded_calibration.py`: median imputation, scaling, and Ridge(alpha=10), trained on the six original Field F observations (June 5 quad 1–4, June 5 standalone, July 12 standalone). It computes four *near-soil* features—median intensity, intensity spread, ExG, and GLCM entropy—after rectifying the selected quadrilateral to 512 × 512. The iPhone implementation approximates the Python/OpenCV feature extractor now archived at `Desktop/Playground Archive/soil_moisture_rf/hernandez_feature_test.py` and **has not yet been numerically matched against it**. No later test labels were used to fit the frozen coefficients.

The earlier Field F accuracy number is **not validated phone-app accuracy**: some later image/sensor alignments were questioned, and a phone camera differs from the drone camera used for training. Results and irrigation previews are research-only; verify with a ground probe before watering.

## Run

Open `SoilScope.xcodeproj` in Xcode, choose your Apple Developer signing team, and run on an ARKit-capable iPhone. A LiDAR model can use automatic scale; other compatible iPhones can use manual scale. No Mac process, endpoint, tunnel, or model upload is required. Simulator camera/LiDAR behavior was not verified.

The Water plan tab fetches today's rain, high temperature, and reference ET₀ from [Open-Meteo](https://open-meteo.com/en/docs) only when requested. A forecast outage leaves litres unavailable. The water volume is a conservative decision-support preview using crop/soil presets, area, efficiency, and a daily cap—not an automatic valve command or a measured root-zone deficit. The ±5 VWC-point display is a what-if scenario, not a confidence interval. Check [Open-Meteo terms](https://open-meteo.com/en/terms) for production use.

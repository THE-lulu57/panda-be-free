import Foundation

public enum PrinterCommand {
    case pause
    case resume
    case stop
    case printSpeed(SpeedLevel)
    case chamberLight(on: Bool)
    case airductMode(mode: Int)
    case gcodeLine(String)
    case startDrying(amsId: Int, temperature: Int, durationMinutes: Int, rotateTray: Bool)
    case stopDrying(amsId: Int)
    case amsFilamentSetting(amsId: Int, trayId: Int, trayInfoIdx: String, trayType: String,
                            trayColor: String, nozzleTempMin: Int, nozzleTempMax: Int)
    case getVersion
    case pushAll
    /// Starts printing a .gcode.3mf file already on the printer's SD card.
    /// - filePath: path relative to the SD root, e.g. "my_model.gcode.3mf"
    /// - plateGcode: e.g. "Metadata/plate_1.gcode" (from the 3mf's Metadata folder)
    /// - amsMapping: nil = no AMS (single external spool). Otherwise one entry
    ///   per filament color used in the plate, each value being the AMS tray
    ///   index (0-3) it should be printed from.
    case projectFile(filePath: String, plateGcode: String, subtaskName: String,
                     useAMS: Bool, amsMapping: [Int]?, flowCalibration: Bool,
                     bedLeveling: Bool, timelapse: Bool)

    public enum DryingPreset: String, CaseIterable, Identifiable, Sendable {
        case pla = "PLA"
        case abs = "ABS"
        case petg = "PETG"
        case tpu = "TPU"
        case pa = "PA"
        case custom = "Custom"

        public var id: String {
            rawValue
        }

        public var label: LocalizedStringResource {
            switch self {
            case .pla: "PLA"
            case .abs: "ABS"
            case .petg: "PETG"
            case .tpu: "TPU"
            case .pa: "PA"
            case .custom: "Custom"
            }
        }

        public var temperature: Int {
            switch self {
            case .pla: 55
            case .abs: 80
            case .petg: 65
            case .tpu: 55
            case .pa: 80
            case .custom: 55
            }
        }

        public var durationMinutes: Int {
            switch self {
            case .pla: 480
            case .abs: 480
            case .petg: 480
            case .tpu: 480
            case .pa: 720
            case .custom: 480
            }
        }
    }

    public enum SpeedLevel: Int, CaseIterable, Identifiable, Sendable {
        case silent = 1
        case standard = 2
        case sport = 3
        case ludicrous = 4

        public var id: Int {
            rawValue
        }

        public var label: LocalizedStringResource {
            switch self {
            case .silent: "Silent"
            case .standard: "Standard"
            case .sport: "Sport"
            case .ludicrous: "Ludicrous"
            }
        }
    }

    public func payload(sequenceId: String = "0") -> Data {
        let dict: [String: Any] = switch self {
        case .pause:
            ["print": ["sequence_id": sequenceId, "command": "pause", "param": ""]]
        case .resume:
            ["print": ["sequence_id": sequenceId, "command": "resume", "param": ""]]
        case .stop:
            ["print": ["sequence_id": sequenceId, "command": "stop", "param": ""]]
        case let .printSpeed(level):
            ["print": ["sequence_id": sequenceId, "command": "print_speed", "param": "\(level.rawValue)"]]
        case let .chamberLight(on):
            ["system": [
                "sequence_id": sequenceId,
                "command": "ledctrl",
                "led_node": "chamber_light",
                "led_mode": on ? "on" : "off",
                "led_on_time": 500,
                "led_off_time": 500,
                "loop_times": 1,
                "interval_time": 1000,
            ]]
        case let .airductMode(mode):
            ["print": [
                "sequence_id": sequenceId,
                "command": "set_airduct",
                "modeId": mode,
                "submode": -1,
            ]]
        case let .gcodeLine(gcode):
            ["print": [
                "sequence_id": sequenceId,
                "command": "gcode_line",
                "param": gcode + "\n",
            ]]
        case let .startDrying(amsId, temperature, durationMinutes, rotateTray):
            ["print": [
                "sequence_id": sequenceId,
                "command": "ams_filament_drying",
                "ams_id": amsId,
                "temp": temperature,
                "cooling_temp": 45,
                "duration": durationMinutes / 60,
                "humidity": 0,
                "mode": 1,
                "rotate_tray": rotateTray,
            ] as [String: Any]]
        case let .stopDrying(amsId):
            ["print": [
                "sequence_id": sequenceId,
                "command": "ams_filament_drying",
                "ams_id": amsId,
                "temp": 0,
                "cooling_temp": 45,
                "duration": 0,
                "humidity": 0,
                "mode": 0,
                "rotate_tray": false,
            ] as [String: Any]]
        case let .amsFilamentSetting(amsId, trayId, trayInfoIdx, trayType,
                                     trayColor, nozzleTempMin, nozzleTempMax):
            ["print": [
                "sequence_id": sequenceId,
                "command": "ams_filament_setting",
                "ams_id": amsId,
                "tray_id": trayId,
                "tray_info_idx": trayInfoIdx,
                "tray_type": trayType,
                "tray_color": trayColor,
                "nozzle_temp_min": nozzleTempMin,
                "nozzle_temp_max": nozzleTempMax,
            ] as [String: Any]]
        case .getVersion:
            ["info": ["sequence_id": sequenceId, "command": "get_version"]]
        case .pushAll:
            ["pushing": ["sequence_id": sequenceId, "command": "pushall"]]
        case let .projectFile(filePath, plateGcode, subtaskName, useAMS, amsMapping,
                               flowCalibration, bedLeveling, timelapse):
            ["print": [
                "sequence_id": sequenceId,
                "command": "project_file",
                "param": plateGcode,
                "plate_idx": 0,
                "project_id": "0",
                "profile_id": "0",
                "task_id": "0",
                "subtask_id": "0",
                "subtask_name": subtaskName,
                "file": "",
                "url": "file:///sdcard/\(filePath)",
                "md5": "",
                "timelapse": timelapse,
                "bed_type": "auto",
                "bed_leveling": bedLeveling,
                "flow_cali": flowCalibration,
                "vibration_cali": false,
                "layer_inspect": false,
                "use_ams": useAMS,
                // Real captured traffic disagrees on the "no override" value:
                // an empty ARRAY vs an empty STRING. Using the empty string
                // here — matches OpenBambuAPI's own reference template AND a
                // separately captured real payload, whereas the empty-array
                // form only appeared in a wiki paraphrase, not a raw capture.
                "ams_mapping": amsMapping.map { $0 as Any } ?? ("" as Any),
            ] as [String: Any]]
        }

        return try! JSONSerialization.data(withJSONObject: dict)
    }

    /// A safe description for logging (no sensitive data).
    public var logDescription: String {
        switch self {
        case .pause: "pause"
        case .resume: "resume"
        case .stop: "stop"
        case let .printSpeed(level): "printSpeed(\(level))"
        case let .chamberLight(on): "chamberLight(\(on ? "on" : "off"))"
        case let .airductMode(mode): "airductMode(\(mode))"
        case let .gcodeLine(gcode): "gcode(\(gcode))"
        case let .startDrying(amsId, temperature, durationMinutes, _):
            "startDrying(ams: \(amsId), temp: \(temperature), duration: \(durationMinutes)m)"
        case let .stopDrying(amsId): "stopDrying(ams: \(amsId))"
        case let .amsFilamentSetting(amsId, trayId, _, trayType, _, _, _):
            "amsFilamentSetting(ams: \(amsId), tray: \(trayId), type: \(trayType))"
        case .getVersion: "getVersion"
        case .pushAll: "pushAll"
        case let .projectFile(filePath, _, subtaskName, useAMS, _, _, _, _):
            "projectFile(\(filePath), task: \(subtaskName), ams: \(useAMS))"
        }
    }
}

// M0 placeholder — HRSenseCompute
// Swift bridge over C ABI compute functions
import HRSenseComputeCxx

public enum ComputeBridge {
    public static func version() -> Int {
        return Int(hrs_compute_init())
    }
}

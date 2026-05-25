import Foundation

final class DiscoveryManager {
    func fetchEndpoints(from discoveryEndpoint: String) -> [String] {
        discoveryEndpoint.withCString { endpointPtr in
            guard let list = opcua_get_endpoints(endpointPtr) else {
                return []
            }
            defer { opcua_endpoint_list_destroy(list) }

            let count = Int(opcua_endpoint_list_count(list))
            guard count > 0 else {
                return []
            }

            var endpoints: [String] = []
            endpoints.reserveCapacity(count)

            for index in 0..<count {
                if let cString = opcua_endpoint_get(list, Int32(index)) {
                    endpoints.append(String(cString: cString))
                }
            }

            return endpoints
        }
    }
}

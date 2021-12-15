//
//  File.swift
//  
//
//  Created by Kelton Person on 12/10/21.
//

import Foundation
import Vapor

let app = try Application(.detect())
//app.servers.use(<#T##makeServer: (Application) -> (Server)##(Application) -> (Server)#>)
defer { app.shutdown() }

app.get("hello") { req in
    return "Hello, world."
}


try app.run()

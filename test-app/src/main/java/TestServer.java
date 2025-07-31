package com.test;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.*;
import java.net.InetSocketAddress;
import java.util.Date;

public class TestServer {
    public static void main(String[] args) throws Exception {
        System.out.println("Starting Java Test Server...");
        
        HttpServer server = HttpServer.create(new InetSocketAddress(9000), 0);
        
        // Root endpoint
        server.createContext("/", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                String response = "Hello from Java Test Server!\n" +
                                "Time: " + new Date() + "\n" +
                                "Version: 1.0.0\n" +
                                "Environment: " + System.getProperty("java.version") + "\n" +
                                "Available endpoints:\n" +
                                "- GET /       : This message\n" +
                                "- GET /health : Health check\n" +
                                "- GET /info   : Server information";
                
                exchange.getResponseHeaders().set("Content-Type", "text/plain");
                exchange.sendResponseHeaders(200, response.length());
                OutputStream os = exchange.getResponseBody();
                os.write(response.getBytes());
                os.close();
                
                System.out.println("[" + new Date() + "] GET / - 200 OK");
            }
        });
        
        // Health check endpoint
        server.createContext("/health", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                String response = "{" +
                    "\"status\":\"healthy\"," +
                    "\"timestamp\":\"" + new Date() + "\"," +
                    "\"uptime\":" + (System.currentTimeMillis()) + "," +
                    "\"version\":\"1.0.0\"" +
                    "}";
                
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, response.length());
                OutputStream os = exchange.getResponseBody();
                os.write(response.getBytes());
                os.close();
                
                System.out.println("[" + new Date() + "] GET /health - 200 OK");
            }
        });
        
        // Server info endpoint
        server.createContext("/info", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                Runtime runtime = Runtime.getRuntime();
                String response = "{" +
                    "\"server\":\"Java Test Server\"," +
                    "\"version\":\"1.0.0\"," +
                    "\"java_version\":\"" + System.getProperty("java.version") + "\"," +
                    "\"os\":\"" + System.getProperty("os.name") + "\"," +
                    "\"memory_total\":" + runtime.totalMemory() + "," +
                    "\"memory_free\":" + runtime.freeMemory() + "," +
                    "\"memory_used\":" + (runtime.totalMemory() - runtime.freeMemory()) + "," +
                    "\"processors\":" + runtime.availableProcessors() + "," +
                    "\"timestamp\":\"" + new Date() + "\"" +
                    "}";
                
                exchange.getResponseHeaders().set("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, response.length());
                OutputStream os = exchange.getResponseBody();
                os.write(response.getBytes());
                os.close();
                
                System.out.println("[" + new Date() + "] GET /info - 200 OK");
            }
        });
        
        server.setExecutor(null);
        System.out.println("Server starting on port 9000...");
        server.start();
        System.out.println("Server started successfully!");
        System.out.println("Access the server at: http://localhost:9000");
        System.out.println("Health check available at: http://localhost:9000/health");
        System.out.println("Server info available at: http://localhost:9000/info");
    }
}

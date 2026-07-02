#!/usr/bin/env python3
# server/master_server/master_server.py
# A lightweight, zero-dependency Python Master Server / Lobby Registry for Godot 4.

import json
import time
import uuid
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# In-memory database of active rooms
# Format: {
#   room_id: {
#       "id": String,
#       "name": String,
#       "ip": String,
#       "port": int,
#       "players": int,
#       "max_players": int,
#       "last_seen": float (timestamp)
#   }
# }
rooms_db = {}
db_lock = threading.Lock()

# Room timeout in seconds (remove room if no heartbeat received)
ROOM_TIMEOUT = 30.0

class MasterServerRequestHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Override to log cleanly to console
        print(f"[MasterServer] {self.address_string()} - {format % args}")

    def send_json_response(self, status_code, data):
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        # Enable CORS for potential web clients
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def do_OPTIONS(self):
        # Handle pre-flight CORS requests
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        # GET /api/rooms - List all active rooms
        if self.path == "/api/rooms":
            with db_lock:
                rooms_list = list(rooms_db.values())
            self.send_json_response(200, {"rooms": rooms_list})
        else:
            self.send_json_response(404, {"error": "Not Found"})

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = b""
        if content_length > 0:
            post_data = self.rfile.read(content_length)

        try:
            body = json.loads(post_data.decode("utf-8")) if post_data else {}
        except json.JSONDecodeError:
            self.send_json_response(400, {"error": "Invalid JSON"})
            return

        # POST /api/rooms/create - Register a new room
        if self.path == "/api/rooms/create":
            name = body.get("name", "Unnamed Room")
            ip = body.get("ip", self.client_address[0]) # Fallback to sender's IP
            port = body.get("port", 9999)
            players = body.get("players", 1)
            max_players = body.get("max_players", 2)

            room_id = str(uuid.uuid4())
            new_room = {
                "id": room_id,
                "name": name,
                "ip": ip,
                "port": int(port),
                "players": int(players),
                "max_players": int(max_players),
                "last_seen": time.time()
            }

            with db_lock:
                rooms_db[room_id] = new_room
                print(f"[MasterServer] Created room {name} ({room_id}) hosted at {ip}:{port}")

            self.send_json_response(201, {"room_id": room_id, "room": new_room})

        # POST /api/rooms/heartbeat - Keep room alive and update player count
        elif self.path == "/api/rooms/heartbeat":
            room_id = body.get("room_id")
            players = body.get("players")

            if not room_id or room_id not in rooms_db:
                self.send_json_response(404, {"error": "Room not found or expired"})
                return

            with db_lock:
                rooms_db[room_id]["last_seen"] = time.time()
                if players is not None:
                    rooms_db[room_id]["players"] = int(players)

            self.send_json_response(200, {"status": "ok"})

        # POST /api/rooms/matchmake - Quick matchmaking request
        elif self.path == "/api/rooms/matchmake":
            # Search for an existing room that has 1 player (waiting for a second player)
            matched_room = None
            with db_lock:
                for room in rooms_db.values():
                    if room["players"] == 1 and room["players"] < room["max_players"]:
                        matched_room = room.copy()
                        break
                
                # If no room has 1 player, check if there's any room at all that's not full
                if not matched_room:
                    for room in rooms_db.values():
                        if room["players"] < room["max_players"]:
                            matched_room = room.copy()
                            break

            if matched_room:
                print(f"[MasterServer] Matched player with room: {matched_room['name']} ({matched_room['id']}) at {matched_room['ip']}:{matched_room['port']}")
                self.send_json_response(200, {
                    "action": "join",
                    "ip": matched_room["ip"],
                    "port": matched_room["port"],
                    "room_id": matched_room["id"]
                })
            else:
                print("[MasterServer] No available rooms for matchmaking. Instructing client to host.")
                self.send_json_response(200, {
                    "action": "host"
                })

        else:
            self.send_json_response(404, {"error": "Not Found"})

    def do_DELETE(self):
        # DELETE /api/rooms/remove - Unregister a room (when host closes it)
        if self.path == "/api/rooms/remove":
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = b""
            if content_length > 0:
                post_data = self.rfile.read(content_length)

            try:
                body = json.loads(post_data.decode("utf-8")) if post_data else {}
            except json.JSONDecodeError:
                self.send_json_response(400, {"error": "Invalid JSON"})
                return

            room_id = body.get("room_id")
            if not room_id:
                self.send_json_response(400, {"error": "Missing room_id"})
                return

            with db_lock:
                if room_id in rooms_db:
                    removed = rooms_db.pop(room_id)
                    print(f"[MasterServer] Removed room {removed['name']} ({room_id})")
                    self.send_json_response(200, {"status": "removed"})
                else:
                    self.send_json_response(404, {"error": "Room not found"})
        else:
            self.send_json_response(404, {"error": "Not Found"})

def cleanup_loop():
    # Background thread to prune inactive rooms
    while True:
        time.sleep(5)
        now = time.time()
        expired_ids = []
        with db_lock:
            for rid, room in rooms_db.items():
                if now - room["last_seen"] > ROOM_TIMEOUT:
                    expired_ids.append(rid)
            for rid in expired_ids:
                expired = rooms_db.pop(rid)
                print(f"[MasterServer] Pruned expired room: {expired['name']} ({rid}) due to missing heartbeat")

def start_server(port=8080):
    # Start the pruning thread as a daemon so it exits when the main thread stops
    pruner = threading.Thread(target=cleanup_loop, daemon=True)
    pruner.start()

    server_address = ("", port)
    httpd = HTTPServer(server_address, MasterServerRequestHandler)
    print(f"[MasterServer] Running registry on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    print("[MasterServer] Stopping server...")
    httpd.server_close()

if __name__ == "__main__":
    import sys
    port = 8080
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print("Usage: python master_server.py [port]")
            sys.exit(1)
    start_server(port)

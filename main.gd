# Main.gd - Attach this to your main scene node (Control or Node2D)

extends Control

# Networking
var peer = ENetMultiplayerPeer.new()
var port = 8910
var max_clients = 10

# Game state
var players = {}  # Dictionary to store player data
var is_host = false
var is_connected = false
var local_username = ""

# UI References
@onready var username_input: LineEdit = $VBoxContainer/UsernameContainer/UsernameInput
@onready var host_button: Button = $VBoxContainer/ButtonContainer/HostButton
@onready var join_button: Button = $VBoxContainer/ButtonContainer/JoinButton
@onready var ip_input: LineEdit = $VBoxContainer/IPContainer/IPInput
@onready var connection_label: Label = $VBoxContainer/ConnectionLabel
@onready var chat_display: TextEdit = $ChatContainer/ChatDisplay
@onready var chat_input: LineEdit = $ChatContainer/ChatInputContainer/ChatInput
@onready var send_button: Button = $ChatContainer/ChatInputContainer/SendButton
@onready var players_list: Label = $PlayersContainer/PlayersList

func _ready():
	# Setup SQLite
	var database = SQLite.new()
	
	
	# Connect UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	send_button.pressed.connect(_on_send_pressed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	
	# Connect username input to update UI when text changes
	username_input.text_changed.connect(_on_username_changed)
	chat_input.text_changed.connect(_on_chat_input_changed)
	
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Set default IP
	ip_input.text = "172.31.1.77"
	
	# Update UI
	_update_ui()

func _on_username_changed(text: String):
	_update_ui()

func _on_chat_input_changed(text: String):
	_update_ui()

func _update_ui():
	connection_label.text = "Status: " + ("Connected as " + ("Host" if is_host else "Client") if is_connected else "Disconnected")
	
	# Enable/disable UI elements
	username_input.editable = not is_connected
	host_button.disabled = is_connected or username_input.text.strip_edges().is_empty()
	join_button.disabled = is_connected or username_input.text.strip_edges().is_empty()
	ip_input.editable = not is_connected
	
	chat_input.editable = is_connected
	send_button.disabled = not is_connected or chat_input.text.strip_edges().is_empty()

func _on_host_pressed():
	if username_input.text.strip_edges().is_empty():
		_add_chat_message("System", "Please enter a username first!")
		return
	
	local_username = username_input.text.strip_edges()
	
	# Create server
	var error = peer.create_server(port, max_clients)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = true
		is_connected = true
		
		# Add host to players dictionary
		players[1] = {"username": local_username, "id": 1}
		
		_add_chat_message("System", "Server started on port " + str(port))
		_add_chat_message("System", "You are now the host/dedicated server")
		_update_players_list()
		_update_ui()
	else:
		_add_chat_message("System", "Failed to create server. Error: " + str(error))

func _on_join_pressed():
	if username_input.text.strip_edges().is_empty():
		_add_chat_message("System", "Please enter a username first!")
		return
	
	local_username = username_input.text.strip_edges()
	
	# Connect to server
	var error = peer.create_client(ip_input.text, port)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		_add_chat_message("System", "Attempting to connect to " + ip_input.text + ":" + str(port))
	else:
		_add_chat_message("System", "Failed to create client. Error: " + str(error))

func _on_send_pressed():
	_send_chat_message()

func _on_chat_submitted(text: String):
	_send_chat_message()

func _send_chat_message():
	var message = chat_input.text.strip_edges()
	if message.is_empty():
		return
	
	# Send message to all peers
	_send_chat_to_all.rpc(local_username, message)
	chat_input.text = ""
	_update_ui()

@rpc("any_peer", "call_local", "reliable")
func _send_chat_to_all(username: String, message: String):
	_add_chat_message(username, message)

func _add_chat_message(username: String, message: String):
	var timestamp = Time.get_datetime_string_from_system().split("T")[1].split(".")[0]
	var formatted_message = "[" + timestamp + "] " + username + ": " + message
	chat_display.text += formatted_message + "\n"
	
	# Auto-scroll to bottom
	chat_display.scroll_vertical = chat_display.get_line_count()

func _on_peer_connected(id: int):
	_add_chat_message("System", "Player " + str(id) + " connected")
	
	if is_host:
		# Send current players list to new client
		_send_players_update.rpc_id(id, players)

func _on_peer_disconnected(id: int):
	var username = players.get(id, {}).get("username", "Unknown")
	_add_chat_message("System", username + " disconnected")
	
	if is_host:
		# Remove player from dictionary
		players.erase(id)
		# Update all clients
		_update_all_players.rpc(players)
		_update_players_list()

func _on_connected_to_server():
	is_connected = true
	_add_chat_message("System", "Connected to server!")
	
	# Send username to server
	_register_player.rpc_id(1, local_username)
	_update_ui()

func _on_connection_failed():
	_add_chat_message("System", "Failed to connect to server")
	multiplayer.multiplayer_peer = null
	_reset_connection()

func _on_server_disconnected():
	_add_chat_message("System", "Disconnected from server")
	multiplayer.multiplayer_peer = null
	_reset_connection()

func _reset_connection():
	is_connected = false
	is_host = false
	players.clear()
	_update_players_list()
	_update_ui()

@rpc("any_peer", "call_remote", "reliable")
func _register_player(username: String):
	if is_host:
		var sender_id = multiplayer.get_remote_sender_id()
		players[sender_id] = {"username": username, "id": sender_id}
		_add_chat_message("System", username + " joined the game")
		
		# Update all clients with new players list
		_update_all_players.rpc(players)
		_update_players_list()

@rpc("authority", "call_local", "reliable")
func _send_players_update(players_data: Dictionary):
	players = players_data
	_update_players_list()

@rpc("authority", "call_local", "reliable")
func _update_all_players(players_data: Dictionary):
	players = players_data
	_update_players_list()

func _update_players_list():
	players_list.text = "Connected Players:\n"
	for player_id in players:
		var player_data = players[player_id]
		var role = " (Host)" if player_id == 1 else " (Client)"
		players_list.text += "• " + player_data.username + role + "\n"

func _input(event):
	if event.is_action_pressed("ui_accept") and chat_input.has_focus():
		_send_chat_message()
	
	# Update send button state when typing
	if event is InputEventKey and chat_input.has_focus():
		call_deferred("_update_ui")

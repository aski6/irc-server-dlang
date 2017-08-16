import std.stdio;
import std.socket;
import std.algorithm.mutation;
import std.conv;
import std.array;
import std.format;
import std.string;

import config;
import client;
import channel;

Channel[string] channels;
Client[] clients;

void main() {
	writefln("This might be an irc server at some point");

	//Receive data from sockets and setup incoming connections.
	auto listener = new TcpSocket(); //Create a socket to listen for incoming connection requests.
	assert(listener.isAlive); //listener must have the isAlive property true.
	listener.blocking = false; //Make listener non-blocking since the program is not multi-threaded, and we want to do things while waiting for sockets to do stuff.
	listener.bind(new InternetAddress(ADDR, PORT));
	listener.listen(1);
	writefln("Listening for incoming connections on address %s, port %d.", ADDR, PORT);
	writefln("");
	auto socketSet = new SocketSet(MAX_CONNECTIONS + 1); // +1 leaves room for the listener socket.
	while (true) {
		socketSet.add(listener);
		foreach (client; clients) {
			//go through each channel the client is part of then copy the channel message queue to the client
			foreach (channel; client.channels) {
				foreach (message; channels[channel].queue) {
					client.queue ~= message;
				}
			}
			//send all messages in the client's message queue to the client.
			foreach (message; client.queue) {
				client.conn.send(message);
			}
			client.queue = [];
			socketSet.add(client.conn); //add all connections to socketSet to be checked for status chages.
		}
		Socket.select(socketSet, null, null);  //get list of sockets that have changed status.
		for (size_t i = 0; i < clients.length; i++) {
			if (socketSet.isSet(clients[i].conn)) { //if socket being checked has a status update.
				char[512] buffer; //irc has a maximum message length of 512 chars, including CR-LF ending (2 chars).
				auto recLen = clients[i].conn.receive(buffer); //recLen stores the length of the data received into the buffer.
				if (recLen == Socket.ERROR) {
					writefln("There was an error receiving from the socket. :(");
				} else if (recLen != 0) {
					processReceived(buffer, recLen, i);
				} else {
					try {
						//try to state address of socket closing, may fail if connections[i] was closed due to an error.
						writefln("Connection from %s closed.", clients[i].conn.remoteAddress().toString());
					} catch (SocketException) {
						writefln("Connection closed.");
					}
					clients[i].conn.close();
					clients = clients.remove(i);
					i--;
				}
			}
		}
		if (socketSet.isSet(listener)) { //if there was a connection request.
			Socket sn = null;
			scope (failure) {
				writefln("Error accepting connection");
				if (sn) {
					sn.close();
				}
			}
			sn = listener.accept();
			assert(sn.isAlive);
			assert(listener.isAlive);
			if (clients.length < MAX_CONNECTIONS) {
				writefln("Connection from %s established.", sn.remoteAddress().toString());
				clients ~= new Client(sn, ("Guest"~to!string(clients.length)));
			} else {
				writefln("Rejected connection from %s: max connections already reached.", sn.remoteAddress().toString());
				sn.close();
				assert(!sn.isAlive);
				assert(listener.isAlive);
			}
		}
		socketSet.reset();
	}
}
void processReceived(char[512] buffer, long recLen, size_t index) {
	writefln("Received %d bytes from %s: %s", recLen, clients[index].conn.remoteAddress().toString(), buffer[0.. recLen]);
	if (buffer[recLen-1] == '\n') {
		string[] messages = split(to!string(buffer[0.. recLen]), '\n');//first split message by the newline char from the message; a check is done above since it is required, and seperating it makes operating each message easier.
		for (int i=0; i < messages.length; i++) {
			messages[i] = removechars(messages[i], "\r"); //Since irc uses windows-style line endings to show the total end of message, remove the extra character since it is not needed for processing the message.
			if(messages[i].length > 0) {
				string[] message = split(messages[i], " "); //split the message into individual args
				if(buffer[0] != ':') { //if there is no prefix
					if(message[0] == "NICK") {
						string reqNick = message[1];
						writefln("requested nick: %s", message[1]);
						if (clients[index].setNick(reqNick) == 0) { //if nick command is sucess.
							writefln("Nick Set: %s", clients[index].nick);
						} else {
							clients[index].queue ~= "433\n";
						}
					} else if (message[0] == "USER") {
						if(message.length >= 4) {
							string realname = message[4.. message.length-1].join();
							clients[index].setup(message[1], message[2], message[3], realname);
							clients[index].queue ~= format("001 %s :Welcome to the Internet Relay Network %s!%s@%s\n", clients[index].nick, clients[index].nick, clients[index].user, clients[index].host);
							clients[index].queue ~= format("002 %s :Your host is %s\n", clients[index].nick, clients[index].server);
						} else {
							clients[index].queue ~= "461\n";
						}
					} else if (message[0] == "JOIN") {clients[index].channels ~= message[1];
						if (!checkChannelExistance(message[1])) {
							channels[message[1]] = new Channel(message[1]);
						}
						clients[index].channels ~= message[1];
						writefln("Joined Channel: %s", message[1]);
					} else if (message[0] == "CAP") {
						clients[index].queue ~= "421\n";
					}
				}
			}
		}
	}
}

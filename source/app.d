/*
Copyright (C) 2017-2018  aski6

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
*/
import std.stdio;
import std.socket;
import std.algorithm.mutation;
import std.algorithm.comparison;
import std.conv;
import std.array;
import std.format;
import std.string;

import config;
import client;
import channel;

void main() {
	writefln("irc-server-dlang  Copyright (C) 2017-2018  aski6
This program comes with ABSOLUTELY NO WARRANTY; for details see LICENCE.md.
This is free software, and you are welcome to redistribute it
under certain conditions; see LICENCE.md for details.");
	writefln("");
	writefln("This might be an irc server at some point");

	//Receive data from sockets and setup incoming connections.
	auto listener = new TcpSocket(); //Create a socket to listen for incoming connection requests.
	assert(listener.isAlive); //Listener must have the isAlive property true.
	listener.blocking = false; //Make listener non-blocking since the program is not multi-threaded.
	listener.bind(new InternetAddress(ADDR, PORT)); //Bind to the address and port specified in config.d.
	listener.listen(1);

	writefln("Listening for incoming connections on address %s, port %d.\n", ADDR, PORT);

	//start the program loop checking sockets.
	auto socketSet = new SocketSet(MAX_CONNECTIONS + 1); //create a socketset with enough slots for the max number of connections. +1 leaves room for the listener socket. The socketset allows us to keep track of which sockets have updates that need processing
	while (true) {

		socketSet.add(listener);//Add the listener socket to the socket set so that we can process any updates from it.

		foreach (client; clients) { //process message queues
			//go through each channel the client is part of then copy the channel message queue to the client
			foreach (channel; client.channels) {
				foreach (message; channels[channel].queue) {
					string[] messageArgs = message.split(" ");
					if (messageArgs[0] != format(":%s", client.nick) && messageArgs[1] == "PRIVMSG") {
						client.queue ~= message;
					}
				}
			}
			//then send all messages in the client's message queue to the client.
			foreach (message; client.queue) {
				client.conn.send(message);
			}
			//clear the client's message queue.
			client.queue = [];
			socketSet.add(client.conn); //add all connections to socketSet to be checked for status chages.
		}
		foreach (channel; channels) {
			channel.queue = [];
		}

		//process updates from our connection's sockets.
		Socket.select(socketSet, null, null);  //get list of sockets that have changed status.
		for (size_t i = 0; i < clients.length; i++) {
			if (socketSet.isSet(clients[i].conn)) { //if socket being checked has a status update.
				char[512] buffer; //irc has a maximum message length of 512 chars, including CR-LF ending (2 chars).
				auto recLen = clients[i].conn.receive(buffer); //recLen stores the length of the data received into the buffer.
				if (recLen == Socket.ERROR) {
					writefln("There was an error receiving from the socket. :(");
				} else if (recLen != 0) {
					processMessage(buffer, recLen, i);
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
			scope (failure) { //if client creation fails, run this.
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
				clients ~= new Client(sn);
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

void processMessage(char[512] buffer, long recLen, size_t clientIndex) {
	writefln("Received %d bytes from %s: %s", recLen, clients[clientIndex].conn.remoteAddress().toString(), buffer[0.. recLen]);

	/*
	   If the message is not valid, we can't process it so exit this function early.
	   All valid messages will end with "\n".
	*/
	if (buffer[recLen-1] != '\n') { //If the message is valid. all valid messages end with \n.
		return;
	}

	Client client = clients[clientIndex];
	//Split the data into separate messages, which will each end with \n. \r characters present in some messages are also removed.
	string[] messages = split(removechars(to!string(buffer[0.. recLen]), "\r"), '\n'); 

	for (int i=0; i < messages.length; i++) { //execute this code for each message.
		//Move onto the next message if there is no data in this message.
		if (messages[i].length < 1) {
		       break;
		}
	
		string[] message = split(messages[i], " "); //Split the message into separated arguments. These are always split by spaces.
		bool hasPrefix = false;
		string prefix;
		/*
		   If the message has a prefix, set the prefix status to true and put the prefix contents into the dedicated string.
		   Then remove the prefix from the message so that the same code can be run with or without a prefix.
		*/
		if (buffer[0] == ':') {
			hasPrefix = true;
			prefix = removechars(message[0], ":");
			message.remove(0);	
		} 

		switch (message[0]) {
			default:
				break;

			/*
		   	The code to handle these messages should perhaps be moved into a dedicated function for each message.
			However, for efficency this will be done when the required updates to these commands are implemented.
			*/	   
			case "USER":
				if(message.length >= 5) { 
					clients[clientIndex].setup(message[1], message[2], message[3], removechars(message[4 .. $].join(" "), ":"));
					clients[clientIndex].queue ~= format("001 %s :Welcome to the Internet Relay Network %s!%s@%s\n", clients[clientIndex].nick, clients[clientIndex].nick, clients[clientIndex].username, clients[clientIndex].hostname);
					//002 message may not be required.
					clients[clientIndex].queue ~= format("002 %s :Your host is %s\n", clients[clientIndex].nick, clients[clientIndex].servername);
				} else {
					clients[clientIndex].queue ~= "461\n";
				}
				break;

			case "NICK":
				writefln("requested nick: %s", message[1]);
				string prevNick = clients[clientIndex].nick;
				if (clients[clientIndex].setNick(message[1])) { //if nick command is sucess.
					writefln("Nick Set: %s\n", clients[clientIndex].nick);
					//Possible solution to the client not appearing to know if their new nickname is accepted.
					if (clients[clientIndex].active) {
						clients[clientIndex].queue ~= format(":%s NICK %s\n", prevNick, message[1]);
					}
				} else {
					clients[clientIndex].queue ~= "433\n";
				}
				break;
			//This channel support is temporary, and is used to test other features.
			case "JOIN": 
				if (!isChannel(message[1])) {
					channels[message[1]] = new Channel();
					writefln(format("Created Channel %s, Current channels are: %s", message[1], channels));
				}
				clients[clientIndex].channels ~= message[1];
				writefln("Joined Channel: %s", message[1]);
				break;

			case "PRIVMSG":
				privmsg(clientIndex, message[1], message[2.. message.length]);
				break;	
			//These commands have either have a direct reply/action, or a planned "no support" response.
			case "PING":
				clients[clientIndex].queue ~= format("PONG %s\n", clients[clientIndex].servername);
				break;

			case "QUIT":
				writefln("Received quit message, releasing nickname and closing sockets");
				clients[clientIndex].quit(to!int(clientIndex));
				clients = clients.remove(clientIndex);
				break;

			case "CAP": //this server does not support this command.
				clients[clientIndex].queue ~= "421\n";
				break;
		}
	}
}

//specific functions for running irc commands.
void privmsg(size_t index, string targetList, string[] messageWords) {
	string[] targets = split(targetList, ",");
	string messageText = messageWords.join(" ");
	writefln("Message to send to %s: %s", targetList, messageText);
	foreach (target; targets) {
		//If the target has a "#" or "&" at the start, it is a channel.
		if (target.indexOfAny("#%") == 0) {
			string message = format(":%s PRIVMSG %s %s\n", clients[index].nick, target, messageText);
			if (!isChannel(target)) {
				writefln(format("%s is not a channel!", target));
			}
			channels[target].queue ~= message;
		}
	}
}

import std.stdio;
import std.socket;
import config;
import std.algorithm.mutation;
import client;

void main() {
	writefln("This might be an irc server at some point");
	auto listener = new TcpSocket();
	assert(listener.isAlive);
	listener.blocking = false;
	listener.bind(new InternetAddress(ADDR, PORT));
	listener.listen(1);
	writefln("Listening for incoming connections on address %s, port %d.", ADDR, PORT);
	writefln("");

	auto socketSet = new SocketSet(MAX_CONNECTIONS + 1); // +1 leaves room for the listener socket.
	Client[] clients;

	while (true) {
		socketSet.add(listener);

		foreach (client; clients) {
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
					writefln("Received %d bytes from %s: %s", recLen, clients[i].conn.remoteAddress().toString(), buffer[0.. recLen]);
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
	/*
	while(true) {
		try {
			Socket server = listener.accept();
			while(server.isAlive()) {
				auto num = server.receive(buffer);
				if(num == 0) { //check that some data has actually been received, if not, our nc socket(used for testing receiving of data from socket) is not active, so start wait for another connection.
					break;
				}
				//writefln(num);
				write(buffer[0.. num]);
			}
		} catch {
			writefln("there was an error :(");
		}
	}
	*/
}

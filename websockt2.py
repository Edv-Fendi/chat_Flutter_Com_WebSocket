import asyncio
import websockets

clientes = set()

async def chat(websocket, path):
    cliente_id = id(websocket)
    print(f"Cliente conectado: {cliente_id}")
    clientes.add(websocket)
    try:
        async for message in websocket:
            mensagem_formatada = f"{message} from {cliente_id}"
            print(f"Mensagem recebida: {mensagem_formatada}")
            for cliente in clientes:
                await cliente.send(mensagem_formatada)
    except websockets.ConnectionClosed:
        print(f"Conexão perdida com o cliente: {cliente_id}")
    finally:
        clientes.remove(websocket)
        print(f"Cliente desconectado: {cliente_id}")

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    start_server = websockets.serve(chat, "127.0.0.1", 8765)

    print("Servidor WebSocket iniciado em ws://127.0.0.1:8765")
    loop.run_until_complete(start_server)
    loop.run_forever()

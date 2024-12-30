import socket
import logging
import time
import numpy as np
import cv2

from log_manager import logger


def receive_image(sock: socket.socket) -> np.ndarray:
    '''
    Receives an image from the socket and returns it as a NumPy array, 
    ready to be displayed as an image. The image comes from a screen capture 
    of the DeSmuME emulator, using the Lua script `stream_socket.lua`.

    By continuously sending screenshots through the socket, the
    gameplay is effectively livestreamed through to OpenCV.
    
    ### Arguments
    #### Required
    - `sock` (socket.socket): socket object to receive image data from
    
    ### Returns
    - `np.ndarray`: image data as a NumPy array
    '''
    # header: 9 bytes for the data length
    length_str = sock.recv(9)
    if not length_str:
        return None
    data_length = int(length_str)

    # content: image data
    data = b''
    while len(data) < data_length:
        packet = sock.recv(data_length - len(data))
        if not packet:
            return None
        data += packet

    image = np.frombuffer(data, dtype=np.uint8)
    image = cv2.imdecode(image, cv2.IMREAD_COLOR)
    return image

def process_image(img: np.ndarray) -> np.ndarray:
    # for now, just convert to grayscale
    img_gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    return img_gray

def compute_button_input(img: np.ndarray) -> int:
    # output format: one byte representing the button inputs
    # 0 if button is not pressed, 1 if button is pressed
    # order: A, Left, Right, Unused, Unused, Unused, Unused, Unused
    # for now, just press and hold the A button (drive forward in Mario Kart)
    return 0b10000000

def send_buttons(sock: socket.socket, buttons: int) -> None:
    '''
    Sends a byte of button input data to the socket, which will be read by the
    Lua script controlling the DeSmuME emulator. The byte is formatted as follows:
    - (MSB)
    - Bit 0: 'A' button
    - Bit 1: Left button
    - Bit 2: Right button
    - Bits 3-7: Unused
    - (LSB)

    ### Arguments
    #### Required
    - `sock` (socket.socket): socket object to send button data to
    - `buttons` (int): byte of button input data
    '''
    data = buttons.to_bytes(1, byteorder='big')
    sock.sendall(data)


def main():

    # set up the server using TCP IPv4
    host, port = "127.0.0.1", 12345
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((host, port))

    while cv2.waitKey(1) & 0xFF != ord('q'):  # loop for accepting connections, press 'q' to quit

        # wait for a connection
        server.listen(1)
        logger.info(f"Listening for connections on {host}:{port}...")
        client_socket, client_address = server.accept()
        logger.info(f"Connection from {client_address}.")

        while cv2.waitKey(1) & 0xFF != ord('q'):  # main loop for processing image frames, press 'q' to quit
            try:
                image = receive_image(client_socket)
                if image is not None:
                    proc_img = process_image(image)
                    button_input = compute_button_input(proc_img)
                    send_buttons(client_socket, button_input)
                    cv2.imshow('Stream from DeSmuME', proc_img)
                else:
                    logger.error(f'Error: Failed to receive image at {time.time()}.')
                    break
            except (ConnectionAbortedError, ConnectionResetError) as e:
                if e.errno in (10053, 10054):
                    logger.error(f'Error: {e}')
                    break
        else:
            logger.info('Quit key pressed. Closing connection and server.')
            cv2.destroyAllWindows()
            break

    logger.info('Closing server.')
    client_socket.close()
    server.close()

if __name__ == '__main__':
    main()

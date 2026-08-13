# archivo principal o archivo orquestador

import sys

EXIT_SUCCESS = 0
EXIT_FAILURE = 1

def etl(args: list[str]) -> int:
    print("Hola mundo")
    return EXIT_SUCCESS


if __name__ == "__main__":
    sys.exit(etl(sys.argv))

"""
Cliente PostgreSQL seguro sobre libpq.so.5 (ctypes) con consultas 100% parametrizadas (PQexecParams).
Se conecta exclusivamente usando el rol restringido app_residencias_user.
"""
import ctypes
import ctypes.util
import os
from pathlib import Path


def _load_dotenv():
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.is_file():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, val)


_load_dotenv()

_DEFAULT_LIBPQ = os.path.expanduser("~/.local/opt/postgresql16/usr/lib/x86_64-linux-gnu/libpq.so.5")
_LIB_PATH = os.environ.get("LIBPQ_PATH") or ctypes.util.find_library("pq") or _DEFAULT_LIBPQ
_libpq = ctypes.CDLL(_LIB_PATH)

CONNECTION_OK = 0
PGRES_COMMAND_OK = 1
PGRES_TUPLES_OK = 2
PG_DIAG_SQLSTATE = ord("C")
PG_DIAG_MESSAGE_PRIMARY = ord("M")
PG_DIAG_MESSAGE_DETAIL = ord("D")

_libpq.PQconnectdb.argtypes = [ctypes.c_char_p]
_libpq.PQconnectdb.restype = ctypes.c_void_p

_libpq.PQstatus.argtypes = [ctypes.c_void_p]
_libpq.PQstatus.restype = ctypes.c_int

_libpq.PQerrorMessage.argtypes = [ctypes.c_void_p]
_libpq.PQerrorMessage.restype = ctypes.c_char_p

_libpq.PQfinish.argtypes = [ctypes.c_void_p]
_libpq.PQfinish.restype = None

_libpq.PQexecParams.argtypes = [
    ctypes.c_void_p,
    ctypes.c_char_p,
    ctypes.c_int,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_char_p),
    ctypes.c_void_p,
    ctypes.c_void_p,
    ctypes.c_int,
]
_libpq.PQexecParams.restype = ctypes.c_void_p

_libpq.PQresultStatus.argtypes = [ctypes.c_void_p]
_libpq.PQresultStatus.restype = ctypes.c_int

_libpq.PQresultErrorMessage.argtypes = [ctypes.c_void_p]
_libpq.PQresultErrorMessage.restype = ctypes.c_char_p

_libpq.PQresultErrorField.argtypes = [ctypes.c_void_p, ctypes.c_int]
_libpq.PQresultErrorField.restype = ctypes.c_char_p

_libpq.PQntuples.argtypes = [ctypes.c_void_p]
_libpq.PQntuples.restype = ctypes.c_int

_libpq.PQnfields.argtypes = [ctypes.c_void_p]
_libpq.PQnfields.restype = ctypes.c_int

_libpq.PQfname.argtypes = [ctypes.c_void_p, ctypes.c_int]
_libpq.PQfname.restype = ctypes.c_char_p

_libpq.PQgetisnull.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
_libpq.PQgetisnull.restype = ctypes.c_int

_libpq.PQgetvalue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
_libpq.PQgetvalue.restype = ctypes.c_char_p

_libpq.PQclear.argtypes = [ctypes.c_void_p]
_libpq.PQclear.restype = None


class PGError(Exception):
    def __init__(self, message: str, sqlstate: str = ""):
        super().__init__(message)
        self.message = message
        self.sqlstate = sqlstate


def get_dsn() -> str:
    host = os.environ.get("PGHOST", "127.0.0.1")
    port = os.environ.get("PGPORT", "5432")
    dbname = os.environ.get("PGDATABASE", "residencias_industrial_db")
    user = os.environ.get("PGUSER", "app_residencias_user")
    password = os.environ.get("PGPASSWORD", "").strip()
    if not password:
        raise PGError("Falta configurar PGPASSWORD en el entorno o en el archivo .env.", "28P01")
    return f"host={host} port={port} dbname={dbname} user={user} password={password} client_encoding=UTF8 connect_timeout=5"


def _encode_param(val):
    if val is None:
        return None
    if isinstance(val, bool):
        return b"true" if val else b"false"
    return str(val).encode("utf-8")


def execute_query(sql: str, params=None):
    """
    Ejecuta SQL parametrizado ($1..$n) mediante PQexecParams.
    Devuelve una lista de diccionarios {columna: valor}.
    """
    conn = _libpq.PQconnectdb(get_dsn().encode("utf-8"))
    if not conn:
        raise PGError("No se pudo asignar conexión libpq.", "08001")

    try:
        if _libpq.PQstatus(conn) != CONNECTION_OK:
            err = (_libpq.PQerrorMessage(conn) or b"Error de conexion PostgreSQL").decode("utf-8", errors="replace")
            raise PGError(err.strip(), "08001")

        param_list = list(params or [])
        n_params = len(param_list)
        if n_params > 0:
            encoded = [_encode_param(v) for v in param_list]
            arr_type = ctypes.c_char_p * n_params
            param_values = arr_type(*encoded)
        else:
            param_values = None

        res = _libpq.PQexecParams(
            conn,
            sql.encode("utf-8"),
            n_params,
            None,
            param_values,
            None,
            None,
            0,
        )
        if not res:
            raise PGError("PQexecParams devolvió resultado nulo.", "58000")

        try:
            status = _libpq.PQresultStatus(res)
            if status not in (PGRES_COMMAND_OK, PGRES_TUPLES_OK):
                raw_state = _libpq.PQresultErrorField(res, PG_DIAG_SQLSTATE)
                raw_primary = _libpq.PQresultErrorField(res, PG_DIAG_MESSAGE_PRIMARY)
                raw_full = _libpq.PQresultErrorMessage(res)
                sqlstate = raw_state.decode("utf-8", errors="replace") if raw_state else ""
                msg = (
                    raw_primary.decode("utf-8", errors="replace")
                    if raw_primary
                    else (raw_full.decode("utf-8", errors="replace") if raw_full else "Error en PostgreSQL")
                )
                raise PGError(msg.strip(), sqlstate.strip())

            if status == PGRES_COMMAND_OK:
                return []

            n_rows = _libpq.PQntuples(res)
            n_cols = _libpq.PQnfields(res)
            cols = [_libpq.PQfname(res, c).decode("utf-8", errors="replace") for c in range(n_cols)]
            rows = []
            for r in range(n_rows):
                row_dict = {}
                for c in range(n_cols):
                    if _libpq.PQgetisnull(res, r, c):
                        row_dict[cols[c]] = None
                    else:
                        row_dict[cols[c]] = _libpq.PQgetvalue(res, r, c).decode("utf-8", errors="replace")
                rows.append(row_dict)
            return rows
        finally:
            _libpq.PQclear(res)
    finally:
        _libpq.PQfinish(conn)


def fetch_one(sql: str, params=None):
    rows = execute_query(sql, params)
    return rows[0] if rows else None


def call_proc(sql: str, params=None):
    rows = execute_query(sql, params)
    return rows[0] if rows else {}
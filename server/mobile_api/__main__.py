"""Запуск сервера командой python -m mobile_api."""
import os
import uvicorn
from .database import ROOT

if __name__ == '__main__':
    uvicorn.run('mobile_api.main:app', host=os.getenv('HOST', '127.0.0.1'), port=int(os.getenv('PORT', '8001')))

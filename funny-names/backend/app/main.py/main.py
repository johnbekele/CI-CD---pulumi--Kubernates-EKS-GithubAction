from fastapi import FastAPI
from pydantic import BaseModel
from typing import List ,Dict
import random
from fastapi.middleware.cors import CORSMiddleware

app=FastAPI()

funny_name=["grag", "chebeso" , "lemmeso", "kuleso" ,"beso" , "tebeju","bortola"]


def randomGenratore(name:List)-> Dict:
    random_name=random.choice(name)
    return {"name":random_name}


origins = [
    "http://localhost.tiangolo.com",
    "https://localhost.tiangolo.com",
    "http://localhost",
    "http://localhost:8080",
    "http://localhost:5173"
] 

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def hello():
    return randomGenratore(funny_name)


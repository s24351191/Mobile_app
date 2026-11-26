"""Ограничения входных данных JSON API."""
from typing import Literal
from pydantic import BaseModel, Field


class PhoneLogin(BaseModel):
    phone: str = Field(min_length=10, max_length=30)


class StaffLogin(BaseModel):
    login: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=1, max_length=200)


class Verification(BaseModel):
    challenge: str = Field(min_length=43, max_length=43)
    code: str = Field(pattern=r'^[0-9]{6}$')


class CartChange(BaseModel):
    quantity: int = Field(ge=0, le=99, strict=True)
    add: bool = False


class Checkout(BaseModel):
    token: str = Field(pattern=r'^[a-f0-9]{32}$')
    recipient: str = Field(min_length=2, max_length=100)
    address: str = Field(min_length=5, max_length=300)
    points: int = Field(ge=0, strict=True)


class ProductFields(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    name_en: str = Field(min_length=2, max_length=150)
    brand: str = Field(min_length=1, max_length=50)
    model: str = Field(min_length=1, max_length=50)
    description: str = Field(min_length=5, max_length=3000)
    description_en: str = Field(min_length=5, max_length=3000)
    price: str = Field(max_length=12)
    is_active: bool = True


class StockChange(BaseModel):
    quantity: int = Field(ge=1, le=10000, strict=True)


class SizePrice(BaseModel):
    price: str | None = Field(default=None, max_length=12)


class OrderAction(BaseModel):
    target: Literal['accepted', 'rejected', 'completed', 'cancelled']

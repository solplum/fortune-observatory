from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class ComplexAnswer(StrictModel):
    id: str = Field(min_length=1, max_length=32)
    question: str = Field(min_length=1, max_length=80)
    answer: str | None = Field(default=None, max_length=80)


class QuestionOut(StrictModel):
    id: str = Field(min_length=1, max_length=32)
    label: str = Field(min_length=1, max_length=80)


class InterpretRequest(StrictModel):
    dream: str = Field(min_length=4, max_length=2000)
    mode: Literal["simple", "complex"] = "simple"
    answers: list[ComplexAnswer] = Field(default_factory=list, max_length=3)


class QuestionsRequest(StrictModel):
    dream: str = Field(min_length=4, max_length=2000)


class QuestionsResponse(StrictModel):
    questions: list[QuestionOut] = Field(min_length=3, max_length=3)


class SourceOut(StrictModel):
    work: str
    quote: str
    channel: Literal["字面", "近邻"]


class InterpretResponse(StrictModel):
    essay: str = ""
    # 思考过程单独成字段随响应发出（不混进 essay）：调用方可渲染为折叠块
    # （与流式通道 think 事件同语义）；E-R3 修复。
    thinking: str = ""
    sources: list[SourceOut] = Field(default_factory=list, max_length=24)
    referral: str | None = None

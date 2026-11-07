"""Regression tests for reconstructed qimen corrections, independent of CLI parity."""
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
import json
import importlib.util
import sys
from pathlib import Path
import pytest
from lunar_python import Solar
from fortune_core.qimen.engine import (build_output, normalize_input, ROTATION_RING,
    GOD_RING_YANG, STAR_RING, DOOR_ELEMENT, WUXING_KE, XUNSHOU_TO_HIDDEN_YI)


def payload(dt, zone='Asia/Shanghai', calendar='solar'):
    return {'calendar_type': calendar, 'time_input': dt, 'location': {'timezone': zone}}


def test_all_24_terms_and_same_instant_pillars():
    terms = Solar.fromYmdHms(2026, 7, 1, 12, 0, 0).getLunar().getJieQiTable()
    names = set()
    for name, solar in terms.items():
        if not any('\u4e00' <= c <= '\u9fff' for c in name):
            continue
        instant = datetime.fromisoformat(solar.toYmdHms()).replace(tzinfo=timezone(timedelta(hours=8)))
        for delta in (-1, 0, 1):
            dt = instant + timedelta(seconds=delta)
            outputs = [build_output(payload(dt.astimezone(ZoneInfo(z)).strftime('%Y-%m-%d %H:%M:%S'), z))
                       for z in ('Asia/Shanghai', 'UTC', 'America/New_York', 'Pacific/Auckland')]
            ref = outputs[0]
            if delta >= 0:
                assert ref['calendar']['jieqi']['active_jie'] == name
                names.add(name)
            else:
                assert ref['calendar']['jieqi']['active_jie'] != name
            for out in outputs:
                assert [out['ganzhi'][k] for k in ('year', 'month')] == [ref['ganzhi'][k] for k in ('year', 'month')]
                assert out['calendar']['jieqi']['active_jie'] == ref['calendar']['jieqi']['active_jie']
                assert datetime.fromisoformat(out['calendar']['jieqi']['active_jie_started_at']) == datetime.fromisoformat(ref['calendar']['jieqi']['active_jie_started_at'])
    assert len(names) == 24


@pytest.mark.parametrize('year', [1849, 1900, 1950, 2000, 2026, 2100, 2150])
def test_range_invariants_and_cli_bytes(year):
    spec = importlib.util.spec_from_file_location('qimen_cli_corrections', Path(__file__).parents[2] / 'skills/qimen-dunjia/scripts/qimen_cli.py')
    cli = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = cli
    spec.loader.exec_module(cli)
    for month in range(1, 13):
        p = payload(f'{year}-{month:02d}-15 12:30:00')
        out = build_output(p)
        assert json.dumps(out, ensure_ascii=False, indent=2) == json.dumps(cli.build_output(p), ensure_ascii=False, indent=2)
        chart = out['chart']
        palaces = {p['palace']: p for p in chart['palaces']}
        direction = 1 if chart['dun_type'] == '阳遁' else -1
        start = ROTATION_RING.index(chart['zhifu']['palace'])
        assert [palaces[ROTATION_RING[(start + direction * i) % 8]]['god'] for i in range(8)] == GOD_RING_YANG
        for name, pillar in [('year_stem', 'year'), ('month_stem', 'month')]:
            gz = out['ganzhi'][pillar]
            assert chart[name]['stem'] == (XUNSHOU_TO_HIDDEN_YI[gz] if gz[0] == '甲' else gz[0])
        for palace in palaces.values():
            if palace['is_center']:
                continue
            patterns = {x['name'] for x in chart['detected_patterns'] if x['palace'] == palace['palace']}
            assert ('门迫' in patterns) == (WUXING_KE[DOOR_ELEMENT[palace['door']]] == palace['element'])
            assert ('反吟' in patterns) == (10 - ROTATION_RING[STAR_RING.index(palace['star'])] == palace['palace'])


@pytest.mark.parametrize('date', ['2026-02-30', '2026-03-01 12', '2026-03-01 12:00:01:02', '2026-03-01 12:00 garbage', '2026--03-01', '+2026-03-01', '2026-03-01 24:00'])
def test_invalid_solar_dates(date):
    with pytest.raises(ValueError):
        normalize_input(payload(date))


@pytest.mark.parametrize('date', ['2026-03-08 02:30', '2026-11-01 01:30'])
def test_dst_gap_and_fold(date):
    with pytest.raises(ValueError):
        normalize_input(payload(date, 'America/New_York'))


def test_strict_lunar_and_integer_fields():
    for raw in [dict(year=2026, month=6, day=15, is_leap_month=True),
                dict(year=2025, month=6, day=31), dict(year=2026, month=-1, day=1),
                dict(year=2026, month=1, day=1, is_leap_month='false'),
                dict(year=2026.1, month=1, day=1), dict(year=True, month=1, day=1)]:
        with pytest.raises(ValueError):
            normalize_input(payload(raw, calendar='lunar'))
    valid = normalize_input(payload(dict(year=2025, month=6, day=1, is_leap_month=True), calendar='lunar'))
    assert valid.solar_dt.strftime('%Y-%m-%d') == '2025-07-25'


def test_local_day_hour_are_retained():
    a = build_output(payload('2026-03-24 10:30', 'Asia/Shanghai'))
    b = build_output(payload('2026-03-23 22:30', 'America/New_York'))
    assert a['ganzhi']['year'] == b['ganzhi']['year']
    assert a['ganzhi']['month'] == b['ganzhi']['month']
    assert a['ganzhi']['day'] != b['ganzhi']['day']
    assert a['ganzhi']['time'] != b['ganzhi']['time']


def test_all_six_jia_year_and_month_hidden_stems():
    years = set()
    months = set()
    for year in (1984, 1994, 2004, 2014, 2024, 2034):
        for month in range(1, 13):
            out = build_output(payload(f'{year}-{month:02d}-15 12:00'))
            for pillar, seen in [('year', years), ('month', months)]:
                gz = out['ganzhi'][pillar]
                if gz.startswith('甲'):
                    seen.add(gz)
                    assert out['chart'][pillar + '_stem']['stem'] == XUNSHOU_TO_HIDDEN_YI[gz]
    # Month stems repeat on a five-year cycle: explicitly cover the intervening years.
    for year in range(2020, 2025):
        for month in range(1, 13):
            out = build_output(payload(f'{year}-{month:02d}-15 12:00'))
            gz = out['ganzhi']['month']
            if gz.startswith('甲'):
                months.add(gz)
                assert out['chart']['month_stem']['stem'] == XUNSHOU_TO_HIDDEN_YI[gz]
    assert years == months == set(XUNSHOU_TO_HIDDEN_YI)


def test_star_opposition_is_reachable():
    charts = [build_output(payload(f'2026-03-{day:02d} 12:00'))['chart'] for day in range(1, 29)]
    assert any(any(p['name'] == '反吟' for p in c['detected_patterns']) for c in charts)

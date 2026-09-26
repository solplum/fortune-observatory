# R14 审计辅助：本地搜索「起运日恰为 2/29」的出生数据候选（复刻 service.py 口径）。
# 用途：manifest 无存量 2/29 起运样本，候选经生产 API /v1/charts 复验。
# 注意：此处用民用时近似，生产用真太阳时（apparent_solar），候选需 API 复验。
from lunar_python import Solar

hits = []
for year in range(1990, 2001):
    for month, dmax in ((1, 31), (2, 29)):
        for day in range(15, dmax + 1):
            for hour in range(24):
                solar = Solar.fromYmdHms(year, month, day, hour, 30, 0)
                lunar = solar.getLunar()
                eight = lunar.getEightChar()
                for gender in (1, 0):  # 1=男 0=女
                    yun = eight.getYun(gender)
                    ss = yun.getStartSolar()
                    if ss.getMonth() == 2 and ss.getDay() == 29:
                        hits.append(
                            (year, month, day, hour, gender,
                             f"{ss.getYear()}-{ss.getMonth():02d}-{ss.getDay():02d} "
                             f"{ss.getHour():02d}:{ss.getMinute():02d}")
                        )

print("total hits:", len(hits))
for h in hits[:10]:
    print(h)

#!/usr/bin/env python3
"""Generates EVLog's demo data: three weeks of a made-up Model 3 living in
Fremont, bundled in teslamateapi's shapes. All times are the story's wall-clock
times written as UTC; the app shifts them on load (see Demo.swift). Day zero is
2026-08-28, a Friday. Output: Resources/Demo/demo-*.json.

The route files next to this script hold road geometries from the public OSRM
server (router.project-osrm.org); the underlying map data is (c) OpenStreetMap
contributors, ODbL."""
import json, math, os, random

random.seed(39)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(f"{HERE}/../../Resources/Demo")
os.makedirs(OUT, exist_ok=True)

DAY0 = (2026, 8, 28)  # Friday
FULL_RANGE = 490.0    # km at 100 %
EFF = 0.152           # kWh/km

HOME = (37.5568, -121.9857)
FACTORY = (37.4926, -121.9446)
SUC = (37.5015, -121.9769)
SANTACRUZ = (36.9721, -122.0263)

def load_route(name):
    d = json.load(open(f"{HERE}/route-{name}.json"))
    route = d["routes"][0]
    pts = [(lat, lon) for lon, lat in route["geometry"]["coordinates"]]
    return pts, route["distance"] / 1000

ROUTE_COMMUTE, KM_COMMUTE = load_route("home-factory")
ROUTE_TRIP, KM_TRIP = load_route("home-santacruz")
ROUTE_SC_SUC, KM_SC_SUC = load_route("santacruz-suc")
ROUTE_SUC_HOME, KM_SUC_HOME = load_route("suc-home")

def iso(day, h, m, s=0):
    y, mo, d = DAY0
    total = d + day
    # roll the month backwards from 28 August; enough for -25..0
    while total < 1:
        mo -= 1
        total += 31 if mo in (1, 3, 5, 7, 8) else (30 if mo != 2 else 28)
    return f"{y:04d}-{mo:02d}-{total:02d}T{h:02d}:{m:02d}:{s:02d}Z"

def minutes(day, h, m):
    return day * 1440 + h * 60 + m

def dist_km(a, b):
    dlat = (a[0] - b[0]) * 111.32
    dlon = (a[1] - b[1]) * 111.32 * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlon)

def route_len(route):
    return sum(dist_km(route[i], route[i + 1]) for i in range(len(route) - 1))

def point_at(route, frac):
    total = route_len(route)
    target = total * frac
    run = 0.0
    for i in range(len(route) - 1):
        seg = dist_km(route[i], route[i + 1])
        if run + seg >= target and seg > 0:
            f = (target - run) / seg
            return (route[i][0] + (route[i + 1][0] - route[i][0]) * f,
                    route[i][1] + (route[i + 1][1] - route[i][1]) * f)
        run += seg
    return route[-1]

soc = 76.0          # percent at the story's start
odo = 24318.0       # km
drives, charges, positions = [], [], []
drive_files, charge_files = {}, {}
heater_drives, heater_charges, cold_charges = [], [], []
did, cid = 0, 0

def rng(soc):
    return round(soc / 100 * FULL_RANGE, 2)

def add_drive(day, h, m, route, road_km, dur_min, name_from, name_to,
              heater=False, temp=21.0):
    global soc, odo, did
    did += 1
    energy = road_km * EFF * random.uniform(0.92, 1.10)
    drop = energy / (FULL_RANGE * EFF) * 100
    start_soc, end_soc = soc, soc - drop
    start_odo = odo
    odo += road_km
    speed_avg = road_km / (dur_min / 60)
    speed_max = min(120, speed_avg * random.uniform(1.55, 1.8))
    start = iso(day, h, m)
    eh, em = h + (m + dur_min) // 60, (m + dur_min) % 60
    end = iso(day, eh, em)
    row = {
        "drive_id": did, "start_date": start, "end_date": end,
        "start_address": name_from, "end_address": name_to,
        "odometer_details": {"odometer_start": round(start_odo, 1),
                             "odometer_end": round(odo, 1),
                             "odometer_distance": round(road_km, 1)},
        "duration_min": dur_min,
        "speed_max": round(speed_max), "speed_avg": round(speed_avg),
        "battery_details": {"start_battery_level": round(start_soc),
                            "start_usable_battery_level": round(start_soc) - (3 if heater else 0),
                            "end_battery_level": round(end_soc)},
        "outside_temp_avg": round(temp + random.uniform(-1.5, 1.5), 1),
        "energy_consumed_net": round(energy, 2),
        "consumption_net": round(energy / road_km * 1000, 1),
        "range_rated": {"start_range": rng(start_soc), "end_range": rng(end_soc),
                        "range_diff": round(rng(start_soc) - rng(end_soc), 2)},
    }
    drives.append(row)
    # detail points every 15 s - sparser clips the corners off the map
    n = max(8, int(dur_min * 4))
    pts = []
    for i in range(n + 1):
        f = i / n
        lat, lon = point_at(route, f)
        # triangular speed profile with noise
        sp = speed_max * min(f / 0.2, 1, (1 - f) / 0.15 if f > 0.85 else 1)
        sp = max(0, sp * random.uniform(0.7, 1.0))
        power = sp * 1.3 * random.uniform(0.6, 1.4)
        if random.random() < 0.12 and 0.2 < f < 0.9:
            power = -random.uniform(5, 30)
        t_min = m + dur_min * f
        pts.append({
            "detail_id": did * 1000 + i,
            "date": iso(day, h + int(t_min) // 60, int(t_min) % 60, int((t_min % 1) * 60)),
            "latitude": round(lat, 6), "longitude": round(lon, 6),
            "speed": round(sp), "power": round(power, 1),
            "battery_level": round(start_soc - drop * f),
            "battery_info": {"battery_heater": bool(heater and f < 0.45)},
        })
        if i % 4 == 0:
            positions.append({"date": pts[-1]["date"], "lat": pts[-1]["latitude"],
                              "lon": pts[-1]["longitude"]})
    detail = dict(row)
    detail["drive_details"] = pts
    drive_files[did] = detail
    if heater:
        heater_drives.append(did)
    soc = end_soc
    return did

def add_charge(day, h, m, dur_min, target_soc, address, latlon, dc=False,
               heater=False, cold=False, counter_start=0.0, temp=20.0):
    global soc, cid
    cid += 1
    added = (target_soc - soc) / 100 * FULL_RANGE * EFF
    used = added * (1.08 if dc else 1.12)
    start_soc = soc
    start = iso(day, h, m)
    eh, em = h + (m + dur_min) // 60, (m + dur_min) % 60
    end = iso(day, eh, em)
    row = {
        "charge_id": cid, "start_date": start, "end_date": end,
        "address": address,
        "charge_energy_added": round(added, 2), "charge_energy_used": round(used, 2),
        # generic prices with no currency: DC ~4/kWh, home ~1.5/kWh
        "cost": round(added * (4.0 if dc else 1.5)), "duration_min": dur_min,
        "battery_details": {"start_battery_level": round(start_soc),
                            "start_usable_battery_level": None,
                            "end_battery_level": round(target_soc)},
        "range_rated": {"start_range": rng(start_soc), "end_range": rng(target_soc),
                        "range_diff": round(rng(target_soc) - rng(start_soc), 2)},
        "outside_temp_avg": round(temp + random.uniform(-1, 1), 1),
        "odometer": round(odo, 1),
        "latitude": latlon[0], "longitude": latlon[1],
    }
    charges.append(row)
    n = max(10, dur_min * 3)  # every 20 s
    pts = []
    for i in range(n + 1):
        f = i / n
        lvl = start_soc + (target_soc - start_soc) * f
        if dc:
            power = 150 * min(f / 0.12, 1) * (1 - 0.55 * max(0, (lvl - 55) / 45))
            power = max(35, power) * random.uniform(0.96, 1.02)
        else:
            power = 11 * random.uniform(0.97, 1.0) if 0.02 < f < 0.98 else 3
        t_s = (m + dur_min * f) * 60
        pts.append({
            "detail_id": cid * 1000 + i,
            "date": iso(day, h + int(t_s // 3600), int(t_s % 3600 // 60), int(t_s % 60)),
            "battery_level": round(lvl),
            "usable_battery_level": round(lvl) - (max(0, 4 - round(8 * f)) if cold else 0),
            "charge_energy_added": round(counter_start + added * f, 2),
            "charger_details": {"charger_power": round(power)},
            "fast_charger_info": {"fast_charger_present": dc},
            "battery_info": {"battery_heater": bool(heater and f < 0.5)},
            "outside_temp": row["outside_temp_avg"],
        })
    detail = dict(row)
    detail["charge_details"] = pts
    charge_files[cid] = detail
    if heater:
        heater_charges.append(cid)
    if cold:
        cold_charges.append(cid)
    soc = target_soc
    return cid

def park_drain(hours, per_hour=0.10):
    global soc
    soc = max(5, soc - hours * per_hour * random.uniform(0.7, 1.4))

# ---- three weeks backwards: day -20 .. 0 (day 0 a Friday) ----
for day in range(-20, 1):
    weekday = (day + 4) % 7  # day 0 Friday=4 (mon=0)
    if weekday < 5:  # weekday: the commute
        hm = random.randint(0, 14)
        heater = day in (-18, -4)  # two cold mornings
        add_drive(day, 8, 5 + hm, ROUTE_COMMUTE, KM_COMMUTE + random.uniform(-0.2, 0.3),
                  17 + random.randint(0, 4), "Home", "Tesla Factory",
                  heater=heater, temp=17 if heater else 21)
        park_drain(9, 0.18)  # sentry at work
        add_drive(day, 17, 10 + random.randint(0, 20), list(reversed(ROUTE_COMMUTE)),
                  KM_COMMUTE + random.uniform(-0.2, 0.3), 18 + random.randint(0, 5),
                  "Tesla Factory", "Home", temp=24)
        # charge at home when needed; the last evening becomes two processes in
        # one plug-in - the unbroken level chain is the stitching signal
        if day == -1:
            first = add_charge(day, 19, 45, 25, 74, "Home", HOME)
            soc = 73
            counter = charge_files[first]["charge_details"][-1]["charge_energy_added"]
            add_charge(day, 20, 55, 22, 80, "Home", HOME, counter_start=counter)
        elif soc < 52:
            add_charge(day, 19, 40 + random.randint(0, 15),
                       int((80 - soc) / 100 * FULL_RANGE * EFF / 11 * 60),
                       80, "Home", HOME)
        park_drain(12, 0.06)
    elif weekday == 5 and day == -13:  # Saturday outing to Santa Cruz
        add_drive(day, 9, 0, ROUTE_TRIP, KM_TRIP, 72, "Home", "Santa Cruz Beach", temp=19)
        park_drain(4, 0.25)
        add_drive(day, 13, 45, ROUTE_SC_SUC, KM_SC_SUC, 70, "Santa Cruz Beach",
                  "Tesla Fremont Supercharger", temp=23)
        add_charge(day, 14, 58, 18, 78, "Tesla Fremont Supercharger", SUC,
                   dc=True, heater=True, cold=True, temp=23)
        add_drive(day, 15, 20, ROUTE_SUC_HOME, KM_SUC_HOME, 13,
                  "Tesla Fremont Supercharger", "Home", temp=23)
        park_drain(8, 0.06)
    else:  # weekend rest
        park_drain(24, 0.08)

drives.sort(key=lambda d: d["start_date"], reverse=True)
charges.sort(key=lambda c: c["start_date"], reverse=True)

def write(name, obj):
    with open(f"{OUT}/{name}.json", "w") as f:
        json.dump({"data": obj}, f, separators=(",", ":"))

write("demo-drives", {"drives": drives})
write("demo-charges", {"charges": charges})
for i, d in drive_files.items():
    write(f"demo-drives-{i}", {"drive": d})
for i, c in charge_files.items():
    write(f"demo-charges-{i}", {"charge": c})

write("demo-cars", {"cars": [{
    "car_id": 1, "name": "Demo",
    "car_details": {"model": "3", "trim_badging": "LR", "vin": "5YJ3DEM0M0DE00000",
                    "efficiency": EFF},
    "car_exterior": {"exterior_color": "DeepBlue", "spoiler_type": "None",
                     "wheel_type": "Pinwheel18"},
    "teslamate_details": {"inserted_at": iso(-20, 7, 0)},
    "teslamate_stats": {"total_charges": len(charges), "total_drives": len(drives),
                        "total_updates": 1},
}]})

write("demo-updates", {"updates": [{
    "update_id": 1, "start_date": iso(-10, 2, 30), "end_date": iso(-10, 2, 55),
    "version": "2026.32.4 fa8e372c9c5a",
}]})

write("demo-status", {"status": {
    "display_name": "DEMO MODE", "state": "online", "state_since": iso(0, 7, 2),
    "odometer": round(odo, 1),
    "car_status": {"healthy": True, "locked": True, "sentry_mode": True,
                   "windows_open": False, "doors_open": False, "trunk_open": False,
                   "frunk_open": False, "is_user_present": False},
    "car_details": {"model": "3", "trim_badging": "LR"},
    "car_exterior": {"exterior_color": "DeepBlue", "spoiler_type": "None",
                     "wheel_type": "Pinwheel18"},
    "car_geodata": {"geofence": "Home", "latitude": HOME[0], "longitude": HOME[1]},
    "car_versions": {"version": "2026.32.4", "update_available": False,
                     "update_version": ""},
    "driving_details": {"shift_state": "P", "power": 0, "speed": 0},
    "climate_details": {"is_climate_on": True, "inside_temp": 21.5,
                        "outside_temp": 19.5, "is_preconditioning": True,
                        "climate_keeper_mode": "off"},
    "battery_details": {"est_battery_range": rng(soc), "rated_battery_range": rng(soc),
                        "ideal_battery_range": rng(soc),
                        "battery_level": round(soc), "usable_battery_level": round(soc)},
    "charging_details": {"plugged_in": True, "charging_state": "complete",
                         "charge_energy_added": charges[0]["charge_energy_added"],
                         "charge_limit_soc": 80, "charge_port_door_open": True,
                         "charger_power": 0, "time_to_full_charge": 0,
                         "scheduled_charging_start_time": "0001-01-01T00:00:00Z"},
    "tpms_details": {"tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.9,
                     "tpms_pressure_rl": 2.9, "tpms_pressure_rr": 2.9,
                     "tpms_soft_warning_fl": False, "tpms_soft_warning_fr": False,
                     "tpms_soft_warning_rl": False, "tpms_soft_warning_rr": False},
}})

with open(f"{OUT}/demo-positions.json", "w") as f:
    json.dump(positions, f, separators=(",", ":"))

total = sum(os.path.getsize(f"{OUT}/{n}") for n in os.listdir(OUT))
print(f"drives={len(drives)} charges={len(charges)} positions={len(positions)}")
print(f"heaterDrives={sorted(heater_drives)} heaterCharges={sorted(heater_charges)} cold={sorted(cold_charges)}")
print(f"end soc={soc:.0f}% odo={odo:.0f} km, {len(os.listdir(OUT))} files, {total//1024} kB")

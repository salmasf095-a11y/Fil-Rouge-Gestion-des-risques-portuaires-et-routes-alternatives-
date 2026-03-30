

import requests
import pandas as pd
import time
import os
from datetime import datetime

# ── Configuration ──────────────────────────────────────────
OSRM_BASE_URL = "https://router.project-osrm.org/route/v1/driving"
OUTPUT_PATH = "data/routes/routes_ports_villes.csv"
DELAY_BETWEEN_REQUESTS = 1.0  # secondes (pour ne pas surcharger l'API)

# ── Liste des paires Port → Ville à calculer ───────────────
# Format : (nom_port, nom_ville, iso3, lon_port, lat_port, lon_ville, lat_ville)
PORT_CITY_PAIRS = [
    # Maroc
    ("Port of Casablanca",  "Casablanca",   "MAR", -7.62,  33.60, -7.58,  33.59),
    ("Port of Casablanca",  "Rabat",        "MAR", -7.62,  33.60, -6.84,  34.02),
    ("Port of Casablanca",  "Marrakech",    "MAR", -7.62,  33.60, -8.00,  31.63),
    ("Port of Casablanca",  "Agadir",       "MAR", -7.62,  33.60, -9.59,  30.43),
    ("Port of Tanger Med",  "Tanger",       "MAR", -5.50,  35.88, -5.80,  35.76),
    ("Port of Tanger Med",  "Tetouan",      "MAR", -5.50,  35.88, -5.37,  35.57),
    # Egypte
    ("Port Said",           "Cairo",        "EGY",  32.30,  31.27, 31.25,  30.06),
    ("Port Said",           "Alexandria",   "EGY",  32.30,  31.27, 29.90,  31.20),
    ("Port of Suez",        "Cairo",        "EGY",  32.55,  29.97, 31.25,  30.06),
    # Europe
    ("Port of Rotterdam",   "Amsterdam",    "NLD",   4.13,  51.95,  4.90,  52.37),
    ("Port of Rotterdam",   "Brussels",     "BEL",   4.13,  51.95,  4.35,  50.85),
    ("Port of Antwerp",     "Brussels",     "BEL",   4.40,  51.23,  4.35,  50.85),
    ("Port of Hamburg",     "Berlin",       "DEU",   9.97,  53.55, 13.40,  52.52),
    ("Port of Le Havre",    "Paris",        "FRA",   0.12,  49.48,  2.35,  48.85),
    ("Port of Marseille",   "Lyon",         "FRA",   5.37,  43.30,  4.84,  45.75),
    ("Port of Piraeus",     "Athens",       "GRC",  23.62,  37.95, 23.73,  37.98),
    ("Port of Istanbul",    "Ankara",       "TUR",  28.95,  41.02, 32.85,  39.93),
    # Moyen-Orient
    ("Port of Jebel Ali",   "Dubai",        "ARE",  55.07,  25.02, 55.27,  25.20),
    ("Port of Jebel Ali",   "Abu Dhabi",    "ARE",  55.07,  25.02, 54.37,  24.47),
    ("Port of Jeddah",      "Riyadh",       "SAU",  39.17,  21.48, 46.72,  24.69),
    # Asie
    ("Port of Singapore",   "Kuala Lumpur", "MYS", 103.85,   1.29,101.69,   3.14),
    ("Port of Mumbai",      "Mumbai City",  "IND",  72.83,  18.97, 72.87,  19.07),
    ("Port of Mumbai",      "Pune",         "IND",  72.83,  18.97, 73.86,  18.52),
    ("Port of Colombo",     "Colombo City", "LKA",  79.85,   6.95, 79.85,   6.93),
    ("Port of Busan",       "Seoul",        "KOR", 129.03,  35.10,126.98,  37.57),
    ("Port of Shanghai",    "Shanghai City","CHN", 121.63,  31.23,121.47,  31.23),
    # Afrique
    ("Port of Lagos",       "Lagos City",   "NGA",   3.40,   6.45,  3.39,   6.46),
    ("Port of Durban",      "Johannesburg", "ZAF",  31.05, -29.87, 28.04, -26.20),
    ("Port of Mombasa",     "Nairobi",      "KEN",  39.65,  -4.05, 36.82,  -1.29),
    # Amériques
    ("Port of Santos",      "Sao Paulo",    "BRA", -46.33, -23.95,-46.63, -23.55),
    ("Port of Long Beach",  "Los Angeles",  "USA",-118.20,  33.75,-118.24,  34.05),
    ("Port of New York",    "New York City","USA", -74.02,  40.65, -74.00,  40.71),
]


def call_osrm(lon_start, lat_start, lon_end, lat_end):
    """
    Appelle l'API OSRM pour calculer la route entre deux points.
    Retourne (distance_km, duration_minutes) ou (None, None) en cas d'erreur.
    """
    url = f"{OSRM_BASE_URL}/{lon_start},{lat_start};{lon_end},{lat_end}"
    params = {
        "overview": "false",
        "annotations": "false"
    }

    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()

        if data.get("code") == "Ok" and data.get("routes"):
            route = data["routes"][0]
            distance_km = round(route["distance"] / 1000, 1)
            duration_min = round(route["duration"] / 60)
            return distance_km, duration_min
        else:
            print(f"  ⚠️  OSRM code: {data.get('code')} — pas de route trouvée")
            return None, None

    except requests.exceptions.Timeout:
        print("  ❌ Timeout — API OSRM non accessible")
        return None, None
    except requests.exceptions.ConnectionError:
        print("  ❌ Connexion impossible — vérifie ta connexion internet")
        return None, None
    except Exception as e:
        print(f"  ❌ Erreur inattendue : {e}")
        return None, None


def classify_risk(distance_km, route_type):
    """Calcule un niveau de risque basé sur la distance et le type de route."""
    if distance_km is None:
        return "Unknown"
    if distance_km < 30:
        return "Low"
    elif distance_km < 150:
        return "Low" if route_type == "highway" else "Medium"
    elif distance_km < 500:
        return "Medium"
    else:
        return "High"


def extract_routes():
    """Fonction principale d'extraction."""
    print("=" * 60)
    print("  🚢 EXTRACTION ROUTES — API OSRM")
    print(f"  Démarrage : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Paires à traiter : {len(PORT_CITY_PAIRS)}")
    print("=" * 60)

    # Créer le dossier de sortie si nécessaire
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    results = []
    success = 0
    errors = 0

    for i, (port, city, iso, lon_p, lat_p, lon_c, lat_c) in enumerate(PORT_CITY_PAIRS, 1):
        print(f"\n[{i:02d}/{len(PORT_CITY_PAIRS)}] {port} → {city} ({iso})")

        distance_km, duration_min = call_osrm(lon_p, lat_p, lon_c, lat_c)

        if distance_km is not None:
            route_type = "highway" if distance_km > 100 else "urban"
            risk = classify_risk(distance_km, route_type)
            alt = "Yes" if distance_km > 50 else "No"

            results.append({
                "start_port":            port,
                "destination_city":      city,
                "country_iso":           iso,
                "port_lat":              lat_p,
                "port_lon":              lon_p,
                "city_lat":              lat_c,
                "city_lon":              lon_c,
                "distance_km":           distance_km,
                "duration_minutes":      duration_min,
                "route_type":            route_type,
                "alternative_available": alt,
                "risk_level":            risk,
                "extracted_at":          datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "source":                "OSRM API",
            })
            print(f"  ✅ {distance_km} km — {duration_min} min — Risque: {risk}")
            success += 1
        else:
            print(f"  ❌ Échec pour cette paire")
            errors += 1

        # Pause entre chaque appel API (bonne pratique)
        time.sleep(DELAY_BETWEEN_REQUESTS)

    # Sauvegarde CSV
    df = pd.DataFrame(results)
    df.to_csv(OUTPUT_PATH, index=False)

    print("\n" + "=" * 60)
    print(f"  ✅ Succès   : {success} routes extraites")
    print(f"  ❌ Erreurs  : {errors} paires échouées")
    print(f"  💾 Fichier  : {OUTPUT_PATH}")
    print(f"  📊 Colonnes : {list(df.columns)}")
    print(f"  Fin        : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    return df


if __name__ == "__main__":
    df = extract_routes()
    print("\n📋 Aperçu des 5 premières lignes :")
    print(df.head().to_string(index=False))
    


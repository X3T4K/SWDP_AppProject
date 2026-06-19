import os
import struct
import random
import math
from datetime import datetime, timedelta

def generate_mock_data():
    # Parametri temporali: 8 ore di campionamento (es. dalle 08:00:00 alle 16:00:00)
    start_time = datetime.now().replace(hour=8, minute=0, second=0, microsecond=0)
    duration_hours = 8
    sample_interval_seconds = 10 # Un campione ogni 10 secondi
    total_samples = int((duration_hours * 3600) / sample_interval_seconds)

    print(f"Generazione in corso di {total_samples} campioni per Spettrometro e Microfono...")
    print(f"Periodo: {start_time.strftime('%H:%M:%S')} -> {(start_time + timedelta(hours=duration_hours)).strftime('%H:%M:%S')}")

    # Liste per accumulare i dati per il CSV, per il plot e bytearray per il dump binario
    spec_csv_rows = ["Timestamp,LuceArtificiale,Blue,DeepBlue,Clear\n"]
    mic_csv_rows = ["Timestamp,DB,Peak\n"]

    spec_bin_data = bytearray()
    mic_bin_data = bytearray()

    # Per il plot
    plot_times = []
    plot_db = []
    plot_peak = []
    plot_clear = []
    plot_blue = []
    plot_deep_blue = []
    plot_luce_art = []

    current_time = start_time

    for i in range(total_samples):
        hh = current_time.hour
        mm = current_time.minute
        ss = current_time.second
        
        # Calcoliamo il timestamp in millisecondi (usando la data odierna per coerenza con StorageService)
        timestamp_ms = int(current_time.timestamp() * 1000)

        # Determiniamo il comportamento in base alla fascia oraria
        # 1. 08:00 - 09:30 (Prep. cantiere ed esterni)
        if 8 <= hh < 9 or (hh == 9 and mm < 30):
            # Rumore di sottofondo alto (cantiere all'aperto) con picchi occasionali
            db = int(random.normalvariate(82, 4))
            db = max(40, min(120, db))
            peak = int(db + random.uniform(5, 15))
            peak = max(db, min(130, peak))

            # Luce solare esterna (luminosità medio-alta)
            clear = int(random.normalvariate(18000, 1500))
            blue = int(clear * random.uniform(0.35, 0.42))
            deep_blue = int(clear * random.uniform(0.25, 0.32))
            luce_art = int(random.uniform(50, 150))

        # 2. 09:30 - 10:00 (Riunione di sicurezza al chiuso)
        elif hh == 9 and mm >= 30:
            # Silenzioso (chiacchiericcio)
            db = int(random.normalvariate(52, 3))
            db = max(40, min(70, db))
            peak = int(db + random.uniform(2, 8))
            peak = max(db, min(85, peak))

            # Luce artificiale da ufficio
            clear = int(random.normalvariate(1500, 100))
            luce_art = int(clear * random.uniform(0.80, 0.90))
            blue = int(clear * random.uniform(0.15, 0.20))
            deep_blue = int(clear * random.uniform(0.05, 0.10))

        # 3. 10:00 - 12:00 (Saldatura elettrica e taglio metalli)
        elif 10 <= hh < 12:
            # Molto rumoroso, rumore dinamico con picchi frequenti
            db = int(random.normalvariate(94, 6))
            db = max(50, min(115, db))
            peak = int(db + random.uniform(8, 20))
            peak = max(db, min(130, peak))

            # Attività di saldatura: genera forti picchi di luce blu/deepBlue ad intervalli regolari
            # Simuliamo cicli di saldatura attiva (ogni 2 minuti salda per 30 secondi)
            is_welding = (mm % 2 == 0 and ss < 30)
            if is_welding:
                clear = int(random.normalvariate(35000, 3000))
                blue = int(clear * random.uniform(0.75, 0.85)) # Altissimo spettro blu
                deep_blue = int(clear * random.uniform(0.65, 0.75)) # Altissimo deep blue (UV/Arco)
                luce_art = int(random.normalvariate(3000, 300))
            else:
                # Luce ambiente interna dell'officina
                clear = int(random.normalvariate(3000, 200))
                luce_art = int(clear * random.uniform(0.60, 0.75))
                blue = int(clear * random.uniform(0.20, 0.25))
                deep_blue = int(clear * random.uniform(0.10, 0.15))

        # 4. 12:00 - 13:00 (Pausa pranzo in mensa)
        elif hh == 12:
            # Rumore moderato (voci, piatti)
            db = int(random.normalvariate(62, 4))
            db = max(45, min(80, db))
            peak = int(db + random.uniform(5, 12))
            peak = max(db, min(95, peak))

            # Luce interna mista (artificiale + finestre)
            clear = int(random.normalvariate(4000, 300))
            luce_art = int(clear * random.uniform(0.40, 0.50))
            blue = int(clear * random.uniform(0.25, 0.30))
            deep_blue = int(clear * random.uniform(0.15, 0.20))

        # 5. 13:00 - 15:00 (Uso di martello pneumatico e macchinari pesanti all'aperto)
        elif 13 <= hh < 15:
            # Rumore continuo estremo
            db = int(random.normalvariate(98, 5))
            db = max(60, min(118, db))
            peak = int(db + random.uniform(10, 22))
            peak = max(db, min(135, peak))

            # Luce solare diretta intensa (primo pomeriggio)
            clear = int(random.normalvariate(38000, 2000))
            blue = int(clear * random.uniform(0.38, 0.45))
            deep_blue = int(clear * random.uniform(0.28, 0.35))
            luce_art = int(random.uniform(20, 80))

        # 6. 15:00 - 16:00 (Pulizia cantiere e fine turno)
        else:
            # Rumore in diminuzione
            db = int(random.normalvariate(70, 5))
            db = max(45, min(95, db))
            peak = int(db + random.uniform(5, 15))
            peak = max(db, min(110, peak))

            # Luce solare pomeridiana calante
            clear = int(random.normalvariate(12000, 1000))
            blue = int(clear * random.uniform(0.32, 0.38))
            deep_blue = int(clear * random.uniform(0.22, 0.28))
            luce_art = int(random.uniform(50, 120))

        # Assicuriamoci che tutti i valori di luce siano entro i limiti uint16 (0 - 65535)
        clear = max(0, min(65535, int(clear)))
        blue = max(0, min(65535, int(blue)))
        deep_blue = max(0, min(65535, int(deep_blue)))
        luce_art = max(0, min(65535, int(luce_art)))

        # Assicuriamoci che i valori del microfono siano entro i limiti uint16 e uint8
        db = max(0, min(65535, int(db)))
        peak = max(0, min(255, int(peak)))

        # 1. Aggiunta al formato CSV
        spec_csv_rows.append(f"{timestamp_ms},{luce_art},{blue},{deep_blue},{clear}\n")
        mic_csv_rows.append(f"{timestamp_ms},{db},{peak}\n")

        # Accumuliamo per il plot
        plot_times.append(current_time)
        plot_db.append(db)
        plot_peak.append(peak)
        plot_clear.append(clear)
        plot_blue.append(blue)
        plot_deep_blue.append(deep_blue)
        plot_luce_art.append(luce_art)

        # 2. Aggiunta al formato binario (Little Endian)
        spec_bin_data.extend(struct.pack('<HHHHHHH', hh, mm, ss, luce_art, blue, deep_blue, clear))
        mic_bin_data.extend(struct.pack('<HHHHB', hh, mm, ss, db, peak))

        # Avanzamento del tempo
        current_time += timedelta(seconds=sample_interval_seconds)

    # Scrittura dei file
    os.makedirs('mock_output', exist_ok=True)

    # Scrittura CSV
    with open('mock_output/spectrometer_data.csv', 'w') as f:
        f.writelines(spec_csv_rows)
    with open('mock_output/microphone_data.csv', 'w') as f:
        f.writelines(mic_csv_rows)

    # Scrittura Binari
    with open('mock_output/spectrometer_dump.bin', 'wb') as f:
        f.write(spec_bin_data)
    with open('mock_output/microphone_dump.bin', 'wb') as f:
        f.write(mic_bin_data)

    print("\nGenerazione completata con successo nella cartella 'mock_output'!")
    print(f"File generati:")
    print(f" - CSV Spettrometro: mock_output/spectrometer_data.csv ({len(spec_csv_rows)-1} righe)")
    print(f" - CSV Microfono:     mock_output/microphone_data.csv ({len(mic_csv_rows)-1} righe)")
    print(f" - Dump Binario Spettrometro: mock_output/spectrometer_dump.bin ({len(spec_bin_data)} byte)")
    print(f" - Dump Binario Microfono:    mock_output/microphone_dump.bin ({len(mic_bin_data)} byte)")

    # Generazione del grafico PNG se matplotlib è disponibile
    try:
        import matplotlib.pyplot as plt
        import matplotlib.dates as mdates

        print("\nGenerazione grafico PNG di riepilogo in corso...")
        
        # Imposta stile grafico scuro ed elegante
        plt.style.use('dark_background')
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8), sharex=True)

        # Plot 1: Microfono (Rumore in dBSPL/dBFS)
        ax1.plot(plot_times, plot_db, color='#1f77b4', alpha=0.8, label='Livello Medio (dB)')
        ax1.plot(plot_times, plot_peak, color='#d62728', alpha=0.4, label='Picco (dB)', linestyle=':')
        ax1.axhline(y=85, color='#ff7f0e', linestyle='--', alpha=0.7, label='Soglia di Rischio (85 dB)')
        ax1.set_title("Simulazione Microfono - Livelli di Rumore (8 ore)", fontsize=14, color='white')
        ax1.set_ylabel("Intensità (dB)", fontsize=12)
        ax1.grid(True, alpha=0.2)
        ax1.legend(loc='upper right')
        
        # Colorazione sfondo in base alle attività
        # Prep: 08:00 - 09:30
        ax1.axvspan(start_time, start_time + timedelta(hours=1, minutes=30), color='gray', alpha=0.1)
        ax1.text(start_time + timedelta(minutes=45), 125, "Prep", color='white', ha='center', fontsize=9)
        
        # Safety Meeting: 09:30 - 10:00
        ax1.axvspan(start_time + timedelta(hours=1, minutes=30), start_time + timedelta(hours=2), color='green', alpha=0.1)
        ax1.text(start_time + timedelta(hours=1, minutes=45), 125, "Meeting", color='white', ha='center', fontsize=9)
        
        # Saldatura/Taglio: 10:00 - 12:00
        ax1.axvspan(start_time + timedelta(hours=2), start_time + timedelta(hours=4), color='red', alpha=0.1)
        ax1.text(start_time + timedelta(hours=3), 125, "Saldatura", color='white', ha='center', fontsize=9)
        
        # Pausa Pranzo: 12:00 - 13:00
        ax1.axvspan(start_time + timedelta(hours=4), start_time + timedelta(hours=5), color='green', alpha=0.1)
        ax1.text(start_time + timedelta(hours=4, minutes=30), 125, "Pranzo", color='white', ha='center', fontsize=9)
        
        # Martello/Macchinari: 13:00 - 15:00
        ax1.axvspan(start_time + timedelta(hours=5), start_time + timedelta(hours=7), color='red', alpha=0.1)
        ax1.text(start_time + timedelta(hours=6), 125, "Martello", color='white', ha='center', fontsize=9)

        # Pulizia: 15:00 - 16:00
        ax1.axvspan(start_time + timedelta(hours=7), start_time + timedelta(hours=8), color='gray', alpha=0.1)
        ax1.text(start_time + timedelta(hours=7, minutes=30), 125, "Pulizia", color='white', ha='center', fontsize=9)

        # Plot 2: Spettrometro (Esposizione Luce)
        ax2.plot(plot_times, plot_clear, color='#ffffff', alpha=0.4, label='Luce Totale (Clear)')
        ax2.plot(plot_times, plot_blue, color='#00bfff', alpha=0.8, label='Luce Blu')
        ax2.plot(plot_times, plot_deep_blue, color='#4b0082', alpha=0.8, label='Luce Blu Profondo (Deep Blue)')
        ax2.plot(plot_times, plot_luce_art, color='#ffcc00', alpha=0.6, label='Luce Artificiale')
        ax2.set_title("Simulazione Spettrometro - Esposizione Spettrale (8 ore)", fontsize=14, color='white')
        ax2.set_ylabel("Valore Sensore (raw)", fontsize=12)
        ax2.set_xlabel("Ora del Giorno", fontsize=12)
        ax2.grid(True, alpha=0.2)
        ax2.legend(loc='upper right')

        # Formattazione asse X (tempo)
        ax2.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
        ax2.xaxis.set_major_locator(mdates.HourLocator(interval=1))
        fig.autofmt_xdate()

        plt.tight_layout()
        plot_path = 'mock_output/sensor_data_visualization.png'
        plt.savefig(plot_path, dpi=150)
        plt.close()
        print(f"Grafico PNG salvato con successo in: {plot_path}")

    except ImportError:
        print("\n[Nota] matplotlib non è installato. Per generare anche il grafico PNG, esegui:")
        print("  pip install matplotlib")

if __name__ == "__main__":
    generate_mock_data()

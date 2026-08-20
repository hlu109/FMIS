import csv
import os
import osmium

# ==============================================================================
# CONFIGURATION
# ==============================================================================
HOME = os.path.expanduser("~")
INPUT_PBF = os.path.join(HOME, "Desktop", "north-america-latest.osm.pbf")
OUTPUT_CSV = os.path.join(HOME, "Desktop", "us_interstates_list.csv")

# ==============================================================================
# STREAM HANDLER (Filters strictly for Interstates)
# ==============================================================================
class InterstateCsvExtractor(osmium.SimpleHandler):
    def __init__(self, csv_writer):
        super(InterstateCsvExtractor, self).__init__()
        self.writer = csv_writer

    # FIXED: This is now correctly indented inside the class!
    def way(self, w):
        if "highway" in w.tags and w.tags["highway"] == "motorway":
            ref = w.tags.get("ref", "").strip()
            
            if ref.startswith("I") and any(char.isdigit() for char in ref):
                # ONLY WRITE REF AND NAME HERE
                self.writer.writerow([
                    ref,
                    w.tags.get("name", "")
                ])

# ==============================================================================
# EXECUTION
# ==============================================================================
def main():
    print("Initializing Local Interstate-Only Extraction...")
    
    if not os.path.exists(INPUT_PBF):
        print(f"\n❌ Error: Could not find raw file at: {INPUT_PBF}")
        return

    print("Scanning stream for Interstates... This will take a few minutes.")
    
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f_out:
        writer = csv.writer(f_out)
        
        # ONLY WRITE THE TWO HEADERS HERE
        writer.writerow(["ref", "name"])
        
        handler = InterstateCsvExtractor(writer)
        reader = osmium.io.Reader(INPUT_PBF)
        
        osmium.apply(reader, handler)
        reader.close()

    print("\n✅ Success!")
    print(f"Your Interstates-only CSV is ready on your Desktop: {OUTPUT_CSV}")

if __name__ == "__main__":
    main()
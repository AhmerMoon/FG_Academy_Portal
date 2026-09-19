import os

def extract_flutter_code_to_txt():
    # Get current directory (Flutter root)
    base_dir = os.getcwd()
    
    # Only scan lib/ folder
    lib_dir = os.path.join(base_dir, 'lib')
    
    # Output file
    output_file = os.path.join(base_dir, "flutter_codebase.txt")
    
    if not os.path.isdir(lib_dir):
        print(f"❌ 'lib' folder not found at: {lib_dir}")
        return
    
    collected_files = []
    
    # Walk only inside lib/
    for root, dirs, files in os.walk(lib_dir):
        # Skip hidden folders just in case
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        
        for file in files:
            if file.endswith('.dart'):
                full_path = os.path.join(root, file)
                # Path relative to base_dir (so it shows lib/...)
                rel_path = os.path.relpath(full_path, base_dir).replace(os.sep, '/')
                collected_files.append((rel_path, full_path))
    
    # Sort: lib/main.dart first, then alphabetical
    def sort_key(item):
        path = item[0]
        if path == 'lib/main.dart':
            return (0, path)
        return (1, path)
    
    collected_files.sort(key=sort_key)
    
    # Add pubspec.yaml at the end
    pubspec_path = os.path.join(base_dir, 'pubspec.yaml')
    has_pubspec = os.path.isfile(pubspec_path)
    
    # Write output
    with open(output_file, 'w', encoding='utf-8') as out:
        out.write("=" * 80 + "\n")
        out.write("FLUTTER PROJECT CODEBASE\n")
        out.write(f"Project Root: {base_dir}\n")
        out.write(f"Total Dart Files: {len(collected_files)}\n")
        out.write("=" * 80 + "\n\n")
        
        # Write all lib dart files
        for rel_path, full_path in collected_files:
            try:
                with open(full_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except UnicodeDecodeError:
                with open(full_path, 'r', encoding='latin-1') as f:
                    content = f.read()
            except Exception as e:
                content = f"// Could not read file: {e}"
            
            out.write(f"{rel_path}:\n")
            out.write(content)
            if not content.endswith('\n'):
                out.write('\n')
            out.write("\n\n")
        
        # Write pubspec.yaml at the end
        if has_pubspec:
            try:
                with open(pubspec_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except Exception as e:
                content = f"# Could not read file: {e}"
            
            out.write("pubspec.yaml:\n")
            out.write(content)
            if not content.endswith('\n'):
                out.write('\n')
            out.write("\n\n")
    
    print(f"✅ Done! File saved at: {output_file}")
    print(f"📄 Dart files included: {len(collected_files)}")
    print(f"📦 pubspec.yaml included: {'Yes' if has_pubspec else 'No'}")

if __name__ == "__main__":
    extract_flutter_code_to_txt()
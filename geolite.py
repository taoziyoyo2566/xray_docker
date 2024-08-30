import geoip2.database
import re
import sys
from collections import defaultdict

def get_ip_info(reader_city, reader_asn, ip):
    try:
        city_response = reader_city.city(ip)
        asn_response = reader_asn.asn(ip)
        country = city_response.country.name or "Unknown Country"
        region = city_response.subdivisions.most_specific.name or "Unknown Region"
        city = city_response.city.name or "Unknown City"
        isp = asn_response.autonomous_system_organization or "Unknown ISP"
        return f"{ip} - {city}, {region}, {country} - {isp}"
    except Exception:
        return f"{ip} - Unknown location - Unknown ISP"

def analyze_log(file_path, city_db_path, asn_db_path):
    with geoip2.database.Reader(city_db_path) as reader_city, geoip2.database.Reader(asn_db_path) as reader_asn:
        with open(file_path, 'r') as file:
            log_data = file.readlines()

        ip_info_mapping = {}
        ip_grouped_data = defaultdict(list)

        for line in log_data:
          #  print(f"Processing line: {line.strip()}")  # Debug output

            # 调整正则表达式以匹配时间、IP地址、目标地址
            match = re.search(r'^(\S+\s+\S+) (\d+\.\d+\.\d+\.\d+):\d+ accepted tcp:(\S+):\d+', line)
            if match:
                timestamp = match.group(1)
                ip = match.group(2)
                destination = match.group(3)
                
                #print(f"Matched IP: {ip}, Destination: {destination}, Time: {timestamp}")  # Debug output

                if ip not in ip_info_mapping:
                    ip_info_mapping[ip] = get_ip_info(reader_city, reader_asn, ip)
                
                ip_info = ip_info_mapping[ip]
                ip_grouped_data[ip_info].append((timestamp, destination))

        if not ip_grouped_data:
            print("No matching IP addresses found.")
        else:
            for ip_info, access_list in ip_grouped_data.items():
                print(f"\nIP 信息: {ip_info}")
                print("访问的目标及时间:")
                for timestamp, dest in access_list:
                    print(f"- {timestamp}: {dest}")
                print(f"总计: {len(access_list)} 次访问")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法: python script_name.py ICUS")
        sys.exit(1)

    log_file_path = f"/opt/docker/reality/nodeInfo/{sys.argv[1]}/log/access.log"
    city_db_path = "/usr/local/share/GeoIP/GeoLite2-City.mmdb"
    asn_db_path = "/usr/local/share/GeoIP/GeoLite2-ASN.mmdb"
    analyze_log(log_file_path, city_db_path, asn_db_path)

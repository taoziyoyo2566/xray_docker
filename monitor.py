import geoip2.database
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta
import os

# 预编译正则表达式
LOG_REGEX = re.compile(r'^(\S+\s+\S+) (\d+\.\d+\.\d+\.\d+):\d+ accepted tcp:(\S+):\d+')

def get_ip_info(reader_city, reader_asn, ip):
    """查询IP的地理位置和ISP信息"""
    try:
        city_response = reader_city.city(ip)
        asn_response = reader_asn.asn(ip)
        country = city_response.country.name or "Unknown Country"
        region = city_response.subdivisions.most_specific.name or "Unknown Region"
        city = city_response.city.name or "Unknown City"
        isp = asn_response.autonomous_system_organization or "Unknown ISP"
        return f"{ip} - {city}, {region}, {country} - {isp}"
    except geoip2.errors.AddressNotFoundError:
        return f"{ip} - Unknown location - Unknown ISP"
    except Exception as e:
        print(f"Error fetching IP info for {ip}: {e}")
        return f"{ip} - Error fetching location"

def parse_log_line(line):
    """解析单行日志，返回匹配的IP、时间戳和目标地址"""
    match = LOG_REGEX.search(line)
    if match:
        timestamp = match.group(1)
        ip = match.group(2)
        destination = match.group(3)
        return timestamp, ip, destination
    return None

def analyze_log(file_path, city_db_path, asn_db_path, directory_name_suffix, time_delta=None):
    """分析日志文件，按IP保存其访问目标和时间"""
    with geoip2.database.Reader(city_db_path) as reader_city, geoip2.database.Reader(asn_db_path) as reader_asn:
        ip_info_mapping = {}
        ip_grouped_data = defaultdict(list)

        # 当前时间用于生成目录
        current_time = datetime.now()
        
        # 构建目录名，格式为: <传入参数>-<时间>-<时间后缀>
        dir_name = f"{directory_name_suffix}-{current_time.strftime('%Y%m%d-%H%M%S')}"

        os.makedirs(dir_name, exist_ok=True)

        # 解析日志文件
        with open(file_path, 'r') as file:
            for line in file:
                log_data = parse_log_line(line)
                if log_data:
                    timestamp_str, ip, destination = log_data
                    timestamp = datetime.strptime(timestamp_str, "%Y/%m/%d %H:%M:%S")

                    # 如果提供了时间参数进行过滤
                    if time_delta and timestamp < current_time - time_delta:
                        continue

                    if ip not in ip_info_mapping:
                        # 查询IP信息并缓存
                        ip_info_mapping[ip] = get_ip_info(reader_city, reader_asn, ip)
                    
                    ip_info = ip_info_mapping[ip]
                    ip_grouped_data[ip_info].append((timestamp_str, destination))

        # 处理文件输出
        for ip_info, access_list in ip_grouped_data.items():
            if access_list:
                # 找到最新的访问时间
                last_access_time_str, _ = access_list[-1]
                last_access_time = datetime.strptime(last_access_time_str, "%Y/%m/%d %H:%M:%S")
                formatted_time = last_access_time.strftime("%Y%m%d-%H%M%S")

                # 创建文件名
                file_name = f"{ip_info.split(' - ')[0]}_{formatted_time}_{ip_info.replace(' ', '_').replace(',', '').replace('-', '_')}.txt"
                file_path = os.path.join(dir_name, file_name)

                # 写入文件内容（去除仅有时间和IP的行）
                with open(file_path, 'w') as output_file:
                    for timestamp_str, destination in access_list:
                        if destination and not re.match(r'^\d+\.\d+\.\d+\.\d+$', destination):  # 跳过仅有IP的行
                            output_file.write(f"{timestamp_str}: {destination}\n")
                print(f"访问记录已保存至文件: {file_path}")
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python script_name.py ICUS [1h|1d|1m]")
        sys.exit(1)

    log_file_path = f"/opt/docker/reality/nodeInfo/{sys.argv[1]}/log/access.log"
    city_db_path = "/usr/local/share/GeoIP/GeoLite2-City.mmdb"
    asn_db_path = "/usr/local/share/GeoIP/GeoLite2-ASN.mmdb"

    # 获取第一个参数作为目录名的一部分
    directory_name_suffix = sys.argv[1]

    # 处理时间参数
    time_param = sys.argv[2] if len(sys.argv) > 2 else None
    time_delta = None

    if time_param == "1h":
        directory_name_suffix += "-h"
        time_delta = timedelta(hours=1)
    elif time_param == "1d":
        directory_name_suffix += "-d"
        time_delta = timedelta(days=1)
    elif time_param == "1m":
        directory_name_suffix += "-m"
        time_delta = timedelta(days=30)
    else:
        directory_name_suffix += "-all"

    analyze_log(log_file_path, city_db_path, asn_db_path, directory_name_suffix, time_delta)

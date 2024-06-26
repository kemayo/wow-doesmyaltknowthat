#!/usr/bin/env python

import json
import re
import sys

from bs4 import BeautifulSoup

from fetch import Fetch

WOWHEAD_URL = 'https://www.wowhead.com'
WOWHEAD_TOOLTIP_URL = 'https://nether.wowhead.com/tooltip'


def soup(html):
    return BeautifulSoup(html, "html.parser")


def fetch_data():
    fetch = Fetch("wowhead", cachetime="+200 day")

    data = []
    items_page = fetch('%s/items=9' % WOWHEAD_URL)
    items_soup = soup(items_page)
    item_types = items_soup.find('select', id="filter-facet-type").find_all('option')
    for item_type in item_types:
        type_url = '%s/items/recipes/type:%s?filter=168;1;0' % (WOWHEAD_URL, item_type['value'])
        # search for items of type which teach a spell
        print("Searching for", item_type.string, type_url)

        type_page = fetch(type_url)
        data_match = re.search(r'var listviewitems = \[\{(.+?)\}\];', type_page, re.DOTALL)
        # for data_match in re.finditer(r'var listviewitems = \[\{(.+?)\}\];', type_page, re.DOTALL):)
        if not data_match:
            print("No items found")
            continue

        for itemid_match in re.finditer(r'"id":\s*(\d+)', data_match.group(1)):
            itemid = itemid_match.group(1)

            # this is the super-lightweight page used for the "powered by wowhead" tooltips
            # print("Fetching item", '%s/item/%s' % (WOWHEAD_TOOLTIP_URL, itemid))
            item_page = fetch('%s/item/%s' % (WOWHEAD_TOOLTIP_URL, itemid))
            if type(item_page) == bytes:
                item_page = item_page.decode('utf-8')
            item = json.loads(item_page)

            # Note: there'll be multiple spellid links. I *think* we can trust the first one to be the "teaches" spellid
            spellid_match = re.search(r'<a href="/spell=(\d+)["/]', item["tooltip"])
            if spellid_match:
                print("-", itemid, ":", item["name"], ":", spellid_match.group(1))
                data.append((int(itemid), int(spellid_match.group(1)), item["name"].replace("\'", "'")))
            # else:
            #     print("Couldn't find spellid", itemid, item_page)
    return data


def write_output(filename, data):
    with open(filename, 'w') as f:
        f.write("""-- DO NOT EDIT THIS FILE; run miner.lua to regenerate.
local myname, ns = ...
ns.itemid_to_spellid = {
""")
        for itemid_spellid_name in sorted(data):
            f.write('\t[%d] = %d, -- %s\n' % itemid_spellid_name)
        f.write("}")

if __name__ == '__main__':
    data = fetch_data()
    write_output("../item_spell_map.lua", data)

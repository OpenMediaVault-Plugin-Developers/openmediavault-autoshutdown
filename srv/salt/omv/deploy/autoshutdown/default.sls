# @license   http://www.gnu.org/licenses/gpl.html GPL Version 3
# @author    OpenMediaVault Plugin Developers <plugins@omv-extras.org>
# @copyright Copyright (c) 2019 OpenMediaVault Plugin Developers
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

{% set config = salt['omv_conf.get']('conf.service.autoshutdown') %}

configure_autoshutdown:
  file.managed:
    - name: "/etc/autoshutdown.conf"
    - source:
      - salt://{{ tpldir }}/files/etc-autoshutdown_conf.j2
    - template: jinja
    - context:
        config: {{ config | json }}
    - user: root
    - group: root
    - mode: 644

{% if config.enable | to_bool %}

start_autoshutdown_service:
  service.running:
    - name: autoshutdown
    - enable: True
    - watch:
      - file: configure_autoshutdown

{% else %}

stop_autoshutdown_service:
  service.dead:
    - name: autoshutdown
    - enable: False

{% endif %}

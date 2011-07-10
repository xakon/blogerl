{% extends "base.tpl" %}
{# index template. Name 'index.tpl' reserved. #}

{% block content %}
<h2>Oh, Hello There!</h2>

<ul class="index">
{% for page in pages %}
    <li>
        <span class="date">{{ page.date }}</span> &mdash;
        <a href="{{ url.base }}{{ page.slug }}.html">{{ page.title }}</a>
    </li>
{% endfor %}
</ul>

<img class="index" src="{{ url.img }}squid.png" width="387" height="424" />

{% endblock %}


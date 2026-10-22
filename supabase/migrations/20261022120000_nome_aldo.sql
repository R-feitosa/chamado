-- Nome exibido do Aldo (pedido do gestor em 22/10/2026). Só o nome muda: id, login, chamados e XP ficam iguais.
update chamados.pessoas set nome = 'Aldo Júnior' where nome = 'Aldo' and papel = 'dev';

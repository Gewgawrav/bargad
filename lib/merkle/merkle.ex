defmodule Merkle do

  def new(tree_type, tree_name, hash_function, backend) do
    tree = Bargad.Utils.make_tree(tree_type, tree_name, hash_function, backend) |>  backend.init_backend()
    Map.put(tree, :root, Bargad.Utils.make_hash(tree,<<>>)) |> Map.put(:size, 0)
  end

  def build(tree, data) do
    Map.put(tree, :root, build(tree, data, 0).hash) |> Map.put(:size, length(data))
  end

  def build(tree, [ value | []], _) do
    node = Bargad.Utils.make_node(tree, Bargad.Utils.make_hash(tree, value), [], 1, value)
    Bargad.Utils.set_node(tree,node.hash,node)
    node
  end

  def build(tree, data, _) do
    n = length(data)
    k = Bargad.Utils.closest_pow_2(n)
    left_child = build(tree, Enum.slice(data, 0..(k - 1)), 0)
    right_child = build(tree, Enum.slice(data, k..(n - 1)), 0)

    node = Bargad.Utils.make_node(
      tree,
      Bargad.Utils.make_hash(tree,left_child.hash <> right_child.hash),
      [left_child.hash, right_child.hash],
      left_child.size + right_child.size,
      left_child.metadata <> right_child.metadata
    )

    Bargad.Utils.set_node(tree,node.hash,node)
    node
  end

  def audit_proof(tree, leaf_hash) do

    root =  Bargad.Utils.get_node(tree,tree.root)
    left =  Bargad.Utils.get_node(tree,List.first(root.children))
    right = Bargad.Utils.get_node(tree,List.last(root.children))

    left_result = audit_proof(tree, root, left, leaf_hash)
    right_result = audit_proof(tree, root, right, leaf_hash)

    case Enum.member?(left_result, :found) do
      true ->
        left_result ++ [{right.hash, "R"}]

      false ->
        case Enum.member?(right_result, :found) do
          true -> right_result ++ [{left.hash, "L"}]
          _ -> right_result
        end
    end
  end

  defp audit_proof(tree, parent, %Bargad.Nodes.Node{treeId: _, hash: x, children: [], metadata: _, size: _}, leaf_hash) do
    if leaf_hash == x do
      [:found]
    else
      [:not_found]
    end
  end

  defp audit_proof(tree, parent, child, leaf_hash) do

    left = Bargad.Utils.get_node(tree,List.first(child.children))
    right = Bargad.Utils.get_node(tree,List.last(child.children))

    left_result = audit_proof(tree, child, left, leaf_hash)
    right_result = audit_proof(tree, child, right, leaf_hash)

    case Enum.member?(left_result, :found) do
      true ->
        left_result ++ [{right.hash, "R"}]

      false ->
        case Enum.member?(right_result, :found) do
          true -> right_result ++ [{left.hash, "L"}]
          _ -> right_result
        end
    end
  end

  def verify_audit_proof(leaf_hash, [], _, _) do
    leaf_hash
  end

  def verify_audit_proof(leaf_hash, [{hash, direction} | t], tree, _) do
    case direction do
      "L" -> Bargad.Utils.make_hash(tree, hash <> leaf_hash) |> verify_audit_proof(t, tree,0)
      "R" -> Bargad.Utils.make_hash(tree, leaf_hash <> hash) |> verify_audit_proof(t, tree,0)
    end
  end

  def verify_audit_proof(tree, proof, leaf_hash) do
    if( tree.root == verify_audit_proof(leaf_hash, proof, tree,0)) do
      true
    else 
      false
    end
  end

  defp audit_tree(_, %Bargad.Nodes.Node{treeId: _, hash: x, children: [], metadata: y, size: _}, _) do
    IO.puts x <> " || " <> y
  end

  defp audit_tree(tree, %Bargad.Nodes.Node{treeId: _, hash: x, children: [left,right], metadata: y, size: _}, _) do
      IO.puts x <> " || " <> y
      left = Bargad.Utils.get_node(tree,left)
      right = Bargad.Utils.get_node(tree,right)
      audit_tree(tree,left,0)
      audit_tree(tree,right,0)
  end

  def audit_tree(tree) do
    root = Bargad.Utils.get_node(tree,tree.root)
    audit_tree(tree,root,0)
  end

  def consistency_Proof(tree = %Bargad.Trees.Tree{treeId: _, treeType: _, backend: _, treeName: _, root: root,  size: _, hashFunction: _}, m) do
    root = Bargad.Utils.get_node(tree,root)
    l = :math.ceil(:math.log2(root.size))
    t = trunc(:math.log2(m))
    consistency_Proof(tree, nil, root, {l, t, m, root.size})
  end 

  def consistency_Proof(tree, _, {_, _, 0, _}) do
    []
  end

  def consistency_Proof(tree, sibling, %Bargad.Nodes.Node{ treeId: _, hash: hash, children: [], metadata: _, size: _}, _) do
    [hash]
  end

  def consistency_Proof(tree, sibling, %Bargad.Nodes.Node{ treeId: _, hash: hash, children: [left , right], metadata: _, size: _}, {l, t, m, size}) when l==t do
    size = trunc(:math.pow(2,l))
    m = m - trunc(:math.pow(2,l))
    l = :math.ceil(:math.log2(size))
    t = trunc(:math.log2(m))
    [ hash | consistency_Proof(tree, nil, sibling, {l, t, m, size})]
  end

  def consistency_Proof(tree, sibling, %Bargad.Nodes.Node{ treeId: _, hash: _, children: [left , right], metadata: _, size: _}, {l, t, m, size}) do 
    left = Bargad.Utils.get_node(tree,left)
    right = Bargad.Utils.get_node(tree,right)
    consistency_Proof(tree, right, left, {l-1, t, m, size})
  end

  def verify_consistency_proof([]) do
    
  end

  def verify_consistency_proof(tree, [first, second]) do
    Bargad.Utils.make_hash(tree, first<>second)
  end

  def verify_consistency_proof(tree, [head | tail]) do
    Bargad.Utils.make_hash(tree, head <> verify_consistency_proof(tree,tail))
  end

  def verify_consistency_proof(tree, proof, old_root_hash) do
    hash = verify_consistency_proof(tree, proof)
    if (hash == old_root_hash) do
      true
    else false
    end
  end

  def insert(tree, parent, left = %Bargad.Nodes.Node{ treeId: _, hash: hash, children: [], metadata: m, size: size}, x, l, "L")  do
    right = Bargad.Utils.get_node(tree, List.last(parent.children))
    node = Bargad.Utils.make_node(tree, left, right)
    Bargad.Utils.set_node(tree,node.hash,node)
    node
  end

  def insert(tree, parent, left = %Bargad.Nodes.Node{ treeId: _, hash: hash, children: [], metadata: m, size: size}, x, l, "R")  do
    right = Bargad.Utils.make_node(tree, Bargad.Utils.make_hash(tree, x), [], 1, x)
    Bargad.Utils.set_node(tree,right.hash,right)
    node = Bargad.Utils.make_node(tree, left, right)
    Bargad.Utils.set_node(tree,node.hash,node)
    node
  end

  def insert(tree, parent, root = %Bargad.Nodes.Node{ treeId: _, hash: hash, children: [left, right], metadata: m, size: size}, x, l, d)  do
    left = Bargad.Utils.get_node(tree, left)
    right = Bargad.Utils.get_node(tree, right)
    if left.size < :math.pow(2,l-1) do
      left = insert(tree, root, left, x, l-1,"L")
      right = Bargad.Utils.make_node(tree, Bargad.Utils.make_hash(tree, x), [], 1, x)
      Bargad.Utils.set_node(tree,right.hash,right)
    else
      right = insert(tree, root, right, x, l-1,"R")
    end
    node = Bargad.Utils.make_node(tree, left, right)
    Bargad.Utils.set_node(tree,node.hash,node)
    node
  end

  def insert(tree = %Bargad.Trees.Tree{treeId: _, treeType: _, backend: _, treeName: _, root: _, size: 0, hashFunction: _}, x) do
    node = Bargad.Utils.make_node(tree, Bargad.Utils.make_hash(tree, x), [], 1, x)
    Bargad.Utils.set_node(tree, node.hash, node)
    Map.put(tree, :root, node.hash) |> Map.put(:size, 1)
  end

  def insert(tree = %Bargad.Trees.Tree{treeId: _, treeType: _, backend: _, treeName: _, root: root,  size: size, hashFunction: _}, x) do
    root = Bargad.Utils.get_node(tree, root)
    l = :math.ceil(:math.log2(root.size))
    
    if root.size == :math.pow(2,l) do
      right = Bargad.Utils.make_node(tree, Bargad.Utils.make_hash(tree,x), [], 1, x)
      Bargad.Utils.set_node(tree, right.hash, right)
      root = Bargad.Utils.make_node(tree, root, right)
      Bargad.Utils.set_node(tree,root.hash,root)
      Map.put(tree, :root, root.hash) |> Map.put(:size, size + 1)
    else
      [left, right] = root.children
      left = Bargad.Utils.get_node(tree, left)
      right = Bargad.Utils.get_node(tree, right)
      if left.size < :math.pow(2,l-1) do
        left = insert(tree, root, left, x, l-1,"L")
      else
        right = insert(tree, root, right, x, l-1,"R" )
      end
      root = Bargad.Utils.make_node(tree, left, right)
      Bargad.Utils.set_node(tree,root.hash,root)
      Map.put(tree, :root, root.hash) |> Map.put(:size, size + 1)
    end
  end

end
